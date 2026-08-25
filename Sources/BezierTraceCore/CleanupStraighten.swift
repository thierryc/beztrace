// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupStraighten {
    private static let maximumOffset = 3.0
    private static let axialTangentMaximumDegrees = 10.0
    private static let chordOffAxisMinimumDegrees = 2.0
    private static let axialVetoMinimumChord = 30.0
    private static let collinearMaximumTurnDegrees = 4.0

    static func flattenStraightRuns(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: mergeCollinear(flatten(path.segments)))
    }

    private static func flatten(_ segments: [PathSegment]) -> [PathSegment] {
        let count = segments.count
        return segments.indices.map { index in
            let segment = segments[index]
            guard !segment.isLine,
                  distanceToLine(segment.cubic.control1, curve: segment.cubic) <= maximumOffset,
                  distanceToLine(segment.cubic.control2, curve: segment.cubic) <= maximumOffset
            else { return segment }
            let previousIncoming = endTangent(segments[(index + count - 1) % count])
            let nextOutgoing = startTangent(segments[(index + 1) % count])
            if keepsAxialTangent(
                segment.cubic,
                previousIncoming: previousIncoming,
                nextOutgoing: nextOutgoing
            ) {
                return segment
            }
            return PathSegment(
                cubic: lineCubic(from: segment.cubic.start, to: segment.cubic.end),
                isLine: true
            )
        }
    }

    private static func axis(of vector: Vector2D) -> Bool? {
        guard vector.magnitude >= 1e-9 else { return nil }
        let angle = abs(atan2(vector.dy, vector.dx)) * 180 / .pi
        let horizontal = min(angle, 180 - angle)
        let vertical = abs(90 - angle)
        if horizontal < axialTangentMaximumDegrees, horizontal <= vertical { return true }
        if vertical < axialTangentMaximumDegrees { return false }
        return nil
    }

    private static func offAxisDegrees(_ vector: Vector2D) -> Double {
        let angle = abs(atan2(vector.dy, vector.dx)) * 180 / .pi
        let horizontal = min(angle, 180 - angle)
        return min(horizontal, abs(90 - angle))
    }

    private static func keepsAxialTangent(
        _ curve: CubicBezier,
        previousIncoming: Vector2D,
        nextOutgoing: Vector2D
    ) -> Bool {
        let chord = curve.end - curve.start
        guard chord.magnitude >= axialVetoMinimumChord,
              offAxisDegrees(chord) >= chordOffAxisMinimumDegrees
        else { return false }
        let ends = [
            (curve.control1 - curve.start, previousIncoming),
            (curve.end - curve.control2, nextOutgoing),
        ]
        return ends.contains { pair in
            guard let first = axis(of: pair.0), let second = axis(of: pair.1) else { return false }
            return first == second
        }
    }

    private static func startTangent(_ segment: PathSegment) -> Vector2D {
        if segment.isLine { return segment.cubic.end - segment.cubic.start }
        let first = segment.cubic.control1 - segment.cubic.start
        return first.magnitude > 1e-9 ? first : segment.cubic.control2 - segment.cubic.start
    }

    private static func endTangent(_ segment: PathSegment) -> Vector2D {
        if segment.isLine { return segment.cubic.end - segment.cubic.start }
        let last = segment.cubic.end - segment.cubic.control2
        return last.magnitude > 1e-9 ? last : segment.cubic.end - segment.cubic.control1
    }

    private static func mergeCollinear(_ input: [PathSegment]) -> [PathSegment] {
        var segments = input
        let minimumCosine = cos(collinearMaximumTurnDegrees * .pi / 180)
        while segments.count >= 2 {
            let count = segments.count
            var merged = false
            for index in 0..<count {
                let next = (index + 1) % count
                guard segments[index].isLine, segments[next].isLine,
                      let first = (segments[index].cubic.end - segments[index].cubic.start).normalized(),
                      let second = (segments[next].cubic.end - segments[next].cubic.start).normalized(),
                      first.dot(second) >= minimumCosine
                else { continue }
                segments[index] = PathSegment(
                    cubic: lineCubic(
                        from: segments[index].cubic.start,
                        to: segments[next].cubic.end
                    ),
                    isLine: true
                )
                segments.remove(at: next)
                merged = true
                break
            }
            if !merged { break }
        }
        return segments
    }

    private static func distanceToLine(_ point: Point2D, curve: CubicBezier) -> Double {
        let direction = curve.end - curve.start
        guard direction.magnitude >= 1e-9 else { return point.distance(to: curve.start) }
        return abs(direction.cross(point - curve.start)) / direction.magnitude
    }
}
