// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupDirection {
    static func fixDirections(_ paths: [BezierPathContour]) -> [BezierPathContour] {
        guard !paths.isEmpty else { return [] }
        let polygons = paths.map(flatten)
        let areas = paths.map(signedArea)
        return paths.indices.map { index in
            let depth = paths.indices.filter {
                $0 != index && containsMajority(polygons[index], inside: polygons[$0])
            }.count
            let shouldBeCounterClockwise = depth % 2 == 0
            let isCounterClockwise = areas[index] > 0
            return shouldBeCounterClockwise == isCounterClockwise
                ? paths[index]
                : reversed(paths[index])
        }
    }

    static func signedArea(_ path: BezierPathContour) -> Double {
        path.segments.reduce(0) {
            let start = $1.cubic.start
            let end = $1.cubic.end
            return $0 + start.x * end.y - end.x * start.y
        } / 2
    }

    static func reversed(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: path.segments.reversed().map { segment in
            PathSegment(
                cubic: CubicBezier(
                    start: segment.cubic.end,
                    control1: segment.cubic.control2,
                    control2: segment.cubic.control1,
                    end: segment.cubic.start
                ),
                isLine: segment.isLine
            )
        })
    }

    static func pointInPolygon(_ point: Point2D, polygon: [Point2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let currentPoint = polygon[index]
            let previousPoint = polygon[previous]
            if (currentPoint.y > point.y) != (previousPoint.y > point.y),
               point.x < (previousPoint.x - currentPoint.x) * (point.y - currentPoint.y)
                    / (previousPoint.y - currentPoint.y) + currentPoint.x
            {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }

    private static func flatten(_ path: BezierPathContour) -> [Point2D] {
        var points: [Point2D] = []
        for segment in path.segments {
            if segment.isLine {
                if points.isEmpty { points.append(segment.cubic.start) }
                points.append(segment.cubic.end)
            } else {
                appendFlattened(segment.cubic, tolerance: 1, depth: 0, to: &points)
            }
        }
        return points
    }

    private static func appendFlattened(
        _ curve: CubicBezier,
        tolerance: Double,
        depth: Int,
        to points: inout [Point2D]
    ) {
        if points.isEmpty { points.append(curve.start) }
        let first = distanceToLine(curve.control1, start: curve.start, end: curve.end)
        let second = distanceToLine(curve.control2, start: curve.start, end: curve.end)
        if max(first, second) <= tolerance || depth >= 16 {
            points.append(curve.end)
        } else {
            let split = curve.split(at: 0.5)
            appendFlattened(split.0, tolerance: tolerance, depth: depth + 1, to: &points)
            appendFlattened(split.1, tolerance: tolerance, depth: depth + 1, to: &points)
        }
    }

    private static func containsMajority(_ inner: [Point2D], inside outer: [Point2D]) -> Bool {
        guard !inner.isEmpty else { return false }
        return inner.filter { pointInPolygon($0, polygon: outer) }.count * 2 > inner.count
    }

    private static func distanceToLine(_ point: Point2D, start: Point2D, end: Point2D) -> Double {
        let direction = end - start
        guard direction.magnitude >= 1e-9 else { return point.distance(to: start) }
        return abs(direction.cross(point - start)) / direction.magnitude
    }
}
