// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupSnap {
    private static let roundMaximumDeviation = 1.5
    private static let cornerAnchorBreak = 25.0 * Double.pi / 180
    private static let cornerSnap = 9.0 * Double.pi / 180

    static func toGrid(_ path: BezierPathContour, fine: Double, structure: Double) -> BezierPathContour {
        guard fine > 0 else { return path }
        let snapCoordinate: (Double) -> Double = { value in
            if structure > fine {
                let structural = (value / structure).rounded() * structure
                if abs(value - structural) <= fine { return structural }
            }
            return (value / fine).rounded() * fine
        }
        let snappedStarts = path.segments.map {
            Point2D(x: snapCoordinate($0.cubic.start.x), y: snapCoordinate($0.cubic.start.y))
        }
        return BezierPathContour(segments: path.segments.indices.map { index in
            var segment = path.segments[index]
            segment.cubic.start = snappedStarts[index]
            segment.cubic.end = snappedStarts[(index + 1) % snappedStarts.count]
            return segment
        })
    }

    static func roundHandles(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: path.segments.map { segment in
            guard !segment.isLine else { return segment }
            var result = segment
            let first = Point2D(
                x: segment.cubic.control1.x.rounded(),
                y: segment.cubic.control1.y.rounded()
            )
            let second = Point2D(
                x: segment.cubic.control2.x.rounded(),
                y: segment.cubic.control2.y.rounded()
            )
            let rounded = CubicBezier(
                start: segment.cubic.start,
                control1: first,
                control2: second,
                end: segment.cubic.end
            )
            let shift = (0...16).reduce(0.0) { maximum, sample in
                let t = Double(sample) / 16
                return max(maximum, segment.cubic.point(at: t).distance(to: rounded.point(at: t)))
            }
            if shift <= roundMaximumDeviation { result.cubic = rounded }
            return result
        })
    }

    static func cornerAnchorPoints(_ path: BezierPathContour) -> [Point2D] {
        guard path.segments.count >= 2, let first = path.segments.first else { return [] }
        var anchors = [first.cubic.start]
        var incomingReferences = [first.cubic.start]
        var firstReferences: [Point2D] = []
        for segment in path.segments {
            anchors.append(segment.cubic.end)
            incomingReferences.append(segment.isLine ? segment.cubic.start : segment.cubic.control2)
            firstReferences.append(segment.isLine ? segment.cubic.end : segment.cubic.control1)
        }
        var result: [Point2D] = []
        for index in anchors.indices {
            let anchor = anchors[index]
            let incoming = anchor - incomingReferences[index]
            let outgoingPoint = index < firstReferences.count ? firstReferences[index] : anchors[0]
            let outgoing = outgoingPoint - anchor
            guard incoming.magnitude >= 1e-9, outgoing.magnitude >= 1e-9 else { continue }
            if incoming.dot(outgoing) / (incoming.magnitude * outgoing.magnitude) < cos(cornerAnchorBreak) {
                result.append(anchor)
            }
        }
        return result
    }

    static func smoothInflectionPoints(_ path: BezierPathContour) -> [Point2D] {
        let count = path.segments.count
        guard count >= 2 else { return [] }
        var result: [Point2D] = []
        for index in 0..<count {
            let previous = path.segments[index]
            let next = path.segments[(index + 1) % count]
            guard !previous.isLine, !next.isLine else { continue }
            let point = previous.cubic.end
            let incoming = point - previous.cubic.control2
            let outgoing = next.cubic.control1 - point
            guard let first = incoming.normalized(epsilon: 1e-6),
                  let second = outgoing.normalized(epsilon: 1e-6),
                  first.dot(second) >= 0.97
            else { continue }
            let normal = Vector2D(dx: -outgoing.dy, dy: outgoing.dx)
            let previousSide = (previous.cubic.start - point).dot(normal)
            let nextSide = (next.cubic.end - point).dot(normal)
            if previousSide * nextSide < 0 { result.append(point) }
        }
        return result
    }

    static func horizontalVerticalHandles(
        _ path: BezierPathContour,
        thresholdDegrees: Double,
        skip: [Point2D],
        corners: [Point2D]
    ) -> BezierPathContour {
        let threshold = thresholdDegrees * .pi / 180
        let lineDirections = path.segments.flatMap { segment -> [(Point2D, Vector2D)] in
            guard segment.isLine,
                  let direction = (segment.cubic.end - segment.cubic.start).normalized(epsilon: 1e-9)
            else { return [] }
            return [(segment.cubic.start, direction), (segment.cubic.end, direction)]
        }
        func skipped(_ point: Point2D) -> Bool { skip.contains { $0.distance(to: point) < 1 } }
        func snapThreshold(_ point: Point2D) -> Double {
            corners.contains { $0.distance(to: point) < 1 } ? cornerSnap : threshold
        }
        func line(at point: Point2D) -> Vector2D? {
            lineDirections.first { $0.0.distance(to: point) < 1 }?.1
        }
        return BezierPathContour(segments: path.segments.map { segment in
            guard !segment.isLine else { return segment }
            var result = segment
            if !skipped(segment.cubic.start) {
                result.cubic.control1 = snapHandle(
                    segment.cubic.control1,
                    at: segment.cubic.start,
                    threshold: snapThreshold(segment.cubic.start),
                    line: line(at: segment.cubic.start)
                )
            }
            if !skipped(segment.cubic.end) {
                result.cubic.control2 = snapHandle(
                    segment.cubic.control2,
                    at: segment.cubic.end,
                    threshold: snapThreshold(segment.cubic.end),
                    line: line(at: segment.cubic.end)
                )
            }
            return result
        })
    }

    private static func snapHandle(
        _ handle: Point2D,
        at anchor: Point2D,
        threshold: Double,
        line: Vector2D?
    ) -> Point2D {
        let vector = handle - anchor
        guard vector.dot(vector) >= 1e-12 else { return handle }
        if let line {
            let angle = abs(atan2(vector.cross(line), vector.dot(line)))
            if min(angle, .pi - angle) < threshold {
                return anchor + line * vector.dot(line)
            }
        }
        let angle = abs(atan2(vector.dy, vector.dx))
        if angle < threshold || .pi - angle < threshold {
            return Point2D(x: handle.x, y: anchor.y)
        }
        if abs(angle - .pi / 2) < threshold {
            return Point2D(x: anchor.x, y: handle.y)
        }
        return handle
    }
}
