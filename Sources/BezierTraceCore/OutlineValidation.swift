// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum InternalOutlinePointKind: Equatable, Sendable {
    case line
    case curve
    case offCurve

    var oracleName: String? {
        switch self {
        case .line: "line"
        case .curve: "curve"
        case .offCurve: nil
        }
    }
}

struct InternalOutlinePoint: Equatable, Sendable {
    var position: Point2D
    var kind: InternalOutlinePointKind
    var smooth: Bool
}

struct InternalOutlineContour: Equatable, Sendable {
    var points: [InternalOutlinePoint]

    mutating func normalizeStart() {
        var best: (index: Int, y: Double, x: Double)?
        for index in points.indices where points[index].kind != .offCurve {
            let point = points[index].position
            if best == nil
                || point.y < best!.y - 1e-9
                || (point.y < best!.y + 1e-9 && point.x < best!.x - 1e-9)
            {
                best = (index, point.y, point.x)
            }
        }
        if let best, best.index > 0 {
            points = Array(points[best.index...]) + Array(points[..<best.index])
        }
    }
}

struct ValidatedOutline: Equatable, Sendable {
    var contours: [InternalOutlineContour]
}

enum OutlineValidator {
    private static let maximumPointsPerContour = 4_096
    private static let closureEpsilon = 1e-6
    private static let handleReachMaximum = 0.9

    static func validate(paths: [BezierPathContour]) throws -> ValidatedOutline {
        guard !paths.isEmpty else { throw CoreError.noContours }
        for (contourIndex, path) in paths.enumerated() {
            guard !path.segments.isEmpty else { throw CoreError.invalidClosure(contour: contourIndex) }
            try validateFinite(path)
            try validateClosure(path, contour: contourIndex)
            try validateSegments(path, contour: contourIndex)
            if hasSelfIntersection(path) { throw CoreError.selfIntersection(contour: contourIndex) }
        }
        try validateWinding(paths)
        let contours = try paths.enumerated().map { index, path in
            var contour = try convert(path, contour: index)
            contour.normalizeStart()
            return contour
        }
        return ValidatedOutline(contours: contours)
    }

    private static func validateFinite(_ path: BezierPathContour) throws {
        guard path.segments.allSatisfy({ $0.cubic.isFinite }) else {
            throw CoreError.nonFiniteGeometry
        }
    }

    private static func validateClosure(_ path: BezierPathContour, contour: Int) throws {
        for index in path.segments.indices {
            let next = (index + 1) % path.segments.count
            guard path.segments[index].cubic.end.distance(to: path.segments[next].cubic.start)
                    <= closureEpsilon
            else { throw CoreError.invalidClosure(contour: contour) }
        }
    }

    private static func validateSegments(_ path: BezierPathContour, contour: Int) throws {
        let pointCount = path.segments.reduce(0) { $0 + ($1.isLine ? 1 : 3) }
        guard pointCount <= maximumPointsPerContour else {
            throw CoreError.pointLimitExceeded(
                contour: contour,
                actual: pointCount,
                limit: maximumPointsPerContour
            )
        }
        for (index, segment) in path.segments.enumerated() {
            let curve = segment.cubic
            let chordVector = curve.end - curve.start
            let chord = chordVector.magnitude
            guard chord > 1e-9 else { throw CoreError.degenerateSegment(contour: contour, segment: index) }
            guard !segment.isLine else { continue }
            let first = curve.control1 - curve.start
            let second = curve.control2 - curve.end
            guard let firstDirection = first.normalized(epsilon: 1e-9),
                  let secondDirection = second.normalized(epsilon: 1e-9)
            else { continue }
            let chordDirection = chordVector / chord
            let reach = first.dot(chordDirection) - second.dot(chordDirection)
            if reach > chord * handleReachMaximum + 2 {
                throw CoreError.handleReachExceeded(contour: contour, segment: index)
            }
            if let triangle = ContourRefiner.handleTriangle(
                start: curve.start,
                startDirection: firstDirection,
                end: curve.end,
                endDirection: secondDirection
            ), first.magnitude > triangle.0 + 2 || second.magnitude > triangle.1 + 2 {
                throw CoreError.handleReachExceeded(contour: contour, segment: index)
            }
        }
    }

    private static func validateWinding(_ paths: [BezierPathContour]) throws {
        let polygons = paths.map(flattenPoints)
        for index in paths.indices {
            let depth = paths.indices.filter {
                $0 != index && containsMajority(polygons[index], inside: polygons[$0])
            }.count
            let area = CleanupDirection.signedArea(paths[index])
            guard abs(area) > 1e-9, (area > 0) == (depth % 2 == 0) else {
                throw CoreError.invalidWinding(contour: index)
            }
        }
    }

    private static func convert(_ path: BezierPathContour, contour: Int) throws -> InternalOutlineContour {
        guard let firstSegment = path.segments.first else {
            throw CoreError.invalidClosure(contour: contour)
        }
        var points: [InternalOutlinePoint] = []
        for segment in path.segments {
            if segment.isLine {
                points.append(.init(position: segment.cubic.end, kind: .line, smooth: false))
            } else {
                points.append(.init(position: segment.cubic.control1, kind: .offCurve, smooth: false))
                points.append(.init(position: segment.cubic.control2, kind: .offCurve, smooth: false))
                points.append(.init(position: segment.cubic.end, kind: .curve, smooth: false))
            }
        }
        let first = firstSegment.cubic.start
        let closingKind: InternalOutlinePointKind = path.segments.last!.isLine ? .line : .curve
        if let lastOnCurve = points.lastIndex(where: { $0.kind != .offCurve }),
           abs(points[lastOnCurve].position.x - first.x) < 0.5,
           abs(points[lastOnCurve].position.y - first.y) < 0.5
        { points.remove(at: lastOnCurve) }
        points.insert(.init(position: first, kind: closingKind, smooth: false), at: 0)
        guard points.count <= maximumPointsPerContour else {
            throw CoreError.pointLimitExceeded(
                contour: contour,
                actual: points.count,
                limit: maximumPointsPerContour
            )
        }
        computeSmooth(&points)
        return InternalOutlineContour(points: points)
    }

    private static func computeSmooth(_ points: inout [InternalOutlinePoint]) {
        guard points.count >= 3 else { return }
        for index in points.indices where points[index].kind != .offCurve {
            let previous = points[(index + points.count - 1) % points.count].position
            let current = points[index].position
            let next = points[(index + 1) % points.count].position
            let incoming = current - previous
            let outgoing = next - current
            guard let first = incoming.normalized(epsilon: 0.01),
                  let second = outgoing.normalized(epsilon: 0.01)
            else { continue }
            if abs(first.cross(second)) < 0.174, first.dot(second) > 0 {
                points[index].smooth = true
            }
        }
    }

    private struct FlattenedEdge {
        let start: Point2D
        let end: Point2D
        let order: Int
    }

    private static func hasSelfIntersection(_ path: BezierPathContour) -> Bool {
        var points: [Point2D] = []
        for segment in path.segments {
            let count = segment.isLine ? 1 : 32
            if points.isEmpty { points.append(segment.cubic.start) }
            for step in 1...count {
                points.append(segment.cubic.point(at: Double(step) / Double(count)))
            }
        }
        let edges = zip(points, points.dropFirst()).enumerated().map {
            FlattenedEdge(start: $0.element.0, end: $0.element.1, order: $0.offset)
        }
        guard edges.count >= 4 else { return false }
        for first in edges.indices {
            for second in (first + 1)..<edges.count {
                if second == first + 1 || (first == 0 && second == edges.count - 1) { continue }
                if properlyIntersects(edges[first], edges[second]) { return true }
            }
        }
        return false
    }

    private static func properlyIntersects(_ first: FlattenedEdge, _ second: FlattenedEdge) -> Bool {
        let a = orientation(first.start, first.end, second.start)
        let b = orientation(first.start, first.end, second.end)
        let c = orientation(second.start, second.end, first.start)
        let d = orientation(second.start, second.end, first.end)
        return a * b < -1e-10 && c * d < -1e-10
    }

    private static func orientation(_ a: Point2D, _ b: Point2D, _ c: Point2D) -> Double {
        (b - a).cross(c - a)
    }

    private static func flattenPoints(_ path: BezierPathContour) -> [Point2D] {
        var result: [Point2D] = []
        for segment in path.segments {
            if result.isEmpty { result.append(segment.cubic.start) }
            let samples = segment.isLine ? 1 : 16
            for index in 1...samples {
                result.append(segment.cubic.point(at: Double(index) / Double(samples)))
            }
        }
        return result
    }

    private static func containsMajority(_ inner: [Point2D], inside outer: [Point2D]) -> Bool {
        guard !inner.isEmpty else { return false }
        return inner.filter { CleanupDirection.pointInPolygon($0, polygon: outer) }.count * 2 > inner.count
    }
}
