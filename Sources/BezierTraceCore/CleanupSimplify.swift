// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupSimplify {
    private static let maximumDeviation = 4.0
    private static let smoothMaximumBreak = 12.0 * Double.pi / 180
    private static let extremumAxis = 12.0 * Double.pi / 180
    private static let shortLineMaximum = 40.0
    private static let tipFlankMaximum = 100.0
    private static let tipFlankBreak = 40.0 * Double.pi / 180
    private static let tipFlankAxis = 2.0 * Double.pi / 180
    private static let extremumShadowEpsilon = 0.25
    private static let grid = 24
    private static let handleReachMaximum = 0.9
    private static let samples = 20

    static func removeRedundantPoints(_ path: BezierPathContour) -> BezierPathContour {
        var segments = path.segments
        while segments.count >= 3 {
            let count = segments.count
            var removed = false
            for index in 0..<count {
                let previous = (index + count - 1) % count
                guard let first = lifted(
                    segments[previous],
                    farEndIsHard: hardCorner(before: previous, in: segments)
                ), let second = lifted(
                    segments[index],
                    farEndIsHard: hardCorner(before: (index + 1) % count, in: segments)
                ) else { continue }
                guard !segments[previous].isLine || !segments[index].isLine else { continue }
                guard let merged = tryMerge(first, second) else { continue }
                segments[previous] = PathSegment(cubic: merged, isLine: false)
                segments.remove(at: index)
                removed = true
                break
            }
            if !removed { break }
        }
        return BezierPathContour(segments: segments)
    }

    private static func hardCorner(before index: Int, in segments: [PathSegment]) -> Bool {
        let previous = (index + segments.count - 1) % segments.count
        guard let incoming = endDirection(segments[previous]),
              let outgoing = startDirection(segments[index])
        else { return false }
        return incoming.dot(outgoing) < cos(tipFlankBreak)
    }

    private static func lifted(_ segment: PathSegment, farEndIsHard: Bool) -> CubicBezier? {
        guard segment.isLine else { return segment.cubic }
        let chord = segment.cubic.end - segment.cubic.start
        let maximum = farEndIsHard && !isAxial(chord) ? tipFlankMaximum : shortLineMaximum
        guard chord.magnitude <= maximum else { return nil }
        return lineCubic(from: segment.cubic.start, to: segment.cubic.end)
    }

    private static func tryMerge(_ first: CubicBezier, _ second: CubicBezier) -> CubicBezier? {
        let joint = first.end
        guard let incoming = (joint - first.control2).normalized(),
              let outgoing = (second.control1 - joint).normalized(),
              incoming.dot(outgoing) >= cos(smoothMaximumBreak),
              turnSign(first) * turnSign(second) >= 0,
              let startDirection = (first.control1 - first.start).normalized(),
              let endDirection = (second.control2 - second.end).normalized()
        else { return nil }

        let target = sample(first) + sample(second)
        let high = (first.start.distance(to: first.end) + second.start.distance(to: second.end)) * 1.1
        let chordVector = second.end - first.start
        let chord = chordVector.magnitude
        guard chord >= 1e-9 else { return nil }
        let chordDirection = chordVector / chord
        let reachLimit = chord * handleReachMaximum
        let triangle = ContourRefiner.handleTriangle(
            start: first.start,
            startDirection: startDirection,
            end: second.end,
            endDirection: endDirection
        )
        var best: (deviation: Double, curve: CubicBezier)?
        for firstStep in 1...grid {
            let firstLength = high * Double(firstStep) / Double(grid)
            for secondStep in 1...grid {
                let secondLength = high * Double(secondStep) / Double(grid)
                if firstLength * startDirection.dot(chordDirection)
                    - secondLength * endDirection.dot(chordDirection) > reachLimit
                { continue }
                if let triangle,
                   (firstLength > triangle.0 || secondLength > triangle.1)
                { continue }
                let candidate = CubicBezier(
                    start: first.start,
                    control1: first.start + startDirection * firstLength,
                    control2: second.end + endDirection * secondLength,
                    end: second.end
                )
                let deviation = maximumDeviation(from: target, to: candidate)
                if best == nil || deviation < best!.deviation {
                    best = (deviation, candidate)
                }
            }
        }
        let protected = (isNearAxis(incoming) || isNearAxis(outgoing))
            && isTrueExtremum(joint, among: target)
        guard let best, best.deviation <= maximumDeviation, !protected else { return nil }
        return best.curve
    }

    private static func sample(_ curve: CubicBezier) -> [Point2D] {
        (0...samples).map { curve.point(at: Double($0) / Double(samples)) }
    }

    private static func maximumDeviation(from target: [Point2D], to curve: CubicBezier) -> Double {
        let polyline = sample(curve)
        return target.reduce(0) { result, point in
            max(result, zip(polyline, polyline.dropFirst()).reduce(.infinity) {
                min($0, distance(point, toSegmentFrom: $1.0, to: $1.1))
            })
        }
    }

    private static func distance(_ point: Point2D, toSegmentFrom start: Point2D, to end: Point2D) -> Double {
        let chord = end - start
        let lengthSquared = chord.dot(chord)
        let parameter = lengthSquared < 1e-12
            ? 0
            : min(max((point - start).dot(chord) / lengthSquared, 0), 1)
        return point.distance(to: start + chord * parameter)
    }

    private static func isTrueExtremum(_ point: Point2D, among target: [Point2D]) -> Bool {
        let epsilon = extremumShadowEpsilon
        return target.allSatisfy { $0.x >= point.x - epsilon }
            || target.allSatisfy { $0.x <= point.x + epsilon }
            || target.allSatisfy { $0.y >= point.y - epsilon }
            || target.allSatisfy { $0.y <= point.y + epsilon }
    }

    private static func turnSign(_ curve: CubicBezier) -> Double {
        guard let start = (curve.control1 - curve.start).normalized(),
              let end = (curve.end - curve.control2).normalized()
        else { return 0 }
        let value = start.cross(end)
        // Rust f64::signum treats +0 as +1 and -0 as -1. Degenerate line
        // cubics therefore retain a turn side instead of disabling the
        // clean-profile inflection guard.
        return value.sign == .minus ? -1 : 1
    }

    private static func isNearAxis(_ direction: Vector2D) -> Bool {
        let tolerance = sin(extremumAxis)
        return abs(direction.dx) < tolerance || abs(direction.dy) < tolerance
    }

    private static func isAxial(_ vector: Vector2D) -> Bool {
        guard let direction = vector.normalized() else { return false }
        let tolerance = sin(tipFlankAxis)
        return abs(direction.dx) < tolerance || abs(direction.dy) < tolerance
    }

    private static func startDirection(_ segment: PathSegment) -> Vector2D? {
        let vector = segment.isLine
            ? segment.cubic.end - segment.cubic.start
            : segment.cubic.control1 - segment.cubic.start
        return vector.normalized(epsilon: 1e-9)
    }

    private static func endDirection(_ segment: PathSegment) -> Vector2D? {
        let vector = segment.isLine
            ? segment.cubic.end - segment.cubic.start
            : segment.cubic.end - segment.cubic.control2
        return vector.normalized(epsilon: 1e-9)
    }
}
