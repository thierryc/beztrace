// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupStraighten {
    private static let maximumOffset = 3.0
    private static let curvedMinimumTurn = 12.0 * Double.pi / 180
    private static let curvedMinimumCoherence = 0.80
    private static let curvedMinimumDeviationFraction = 0.025
    private static let axialTangentMaximumDegrees = 10.0
    private static let chordOffAxisMinimumDegrees = 2.0
    private static let axialVetoMinimumChord = 30.0
    private static let collinearMaximumTurnDegrees = 4.0

    static func flattenStraightRuns(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: mergeCollinear(flatten(path.segments)))
    }

    static func containsCurvedFlattenCandidate(_ path: BezierPathContour) -> Bool {
        path.segments.contains { segment in
            guard !segment.isLine, isFlattenCandidate(segment.cubic) else { return false }
            let curve = segment.cubic
            let chord = curve.start.distance(to: curve.end)
            guard chord > 1e-9 else { return false }
            let deviation = max(
                distanceToLine(curve.control1, curve: curve),
                distanceToLine(curve.control2, curve: curve)
            )
            guard deviation / chord >= curvedMinimumDeviationFraction else { return false }
            let samples = (0...8).map { curve.point(at: Double($0) / 8) }
            let turns = (1..<(samples.count - 1)).map { index in
                let incoming = samples[index] - samples[index - 1]
                let outgoing = samples[index + 1] - samples[index]
                return atan2(incoming.cross(outgoing), incoming.dot(outgoing))
            }
            let net = turns.reduce(0, +)
            let absolute = turns.reduce(0) { $0 + abs($1) }
            return abs(net) >= curvedMinimumTurn
                && absolute > 1e-9
                && abs(net) / absolute >= curvedMinimumCoherence
        }
    }

    static func introducesLine(_ path: BezierPathContour) -> Bool {
        let before = path.segments.reduce(0) { $0 + ($1.isLine ? 1 : 0) }
        let after = flattenStraightRuns(path).segments.reduce(0) { $0 + ($1.isLine ? 1 : 0) }
        return after > before
    }

    private static func flatten(_ segments: [PathSegment]) -> [PathSegment] {
        let count = segments.count
        return segments.indices.map { index in
            let segment = segments[index]
            guard !segment.isLine, isFlattenCandidate(segment.cubic)
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

    private static func isFlattenCandidate(_ curve: CubicBezier) -> Bool {
        distanceToLine(curve.control1, curve: curve) <= maximumOffset
            && distanceToLine(curve.control2, curve: curve) <= maximumOffset
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
