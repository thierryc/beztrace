// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupEven {
    private static let ratioTrigger = 1.35
    private static let maximumDeviationAbsolute = 2.5
    private static let maximumDeviationFraction = 0.01
    private static let minimumChord = 30.0
    private static let minimumHandle = 8.0
    private static let grid = 28
    private static let handleReachMaximum = 0.9
    private static let samples = 24

    static func evenHandles(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: path.segments.map { segment in
            guard !segment.isLine else { return segment }
            var result = segment
            let handles = evenSegment(segment.cubic)
            result.cubic.control1 = handles.0
            result.cubic.control2 = handles.1
            return result
        })
    }

    static func capHandles(_ path: BezierPathContour) -> BezierPathContour {
        BezierPathContour(segments: path.segments.map { segment in
            guard !segment.isLine else { return segment }
            var result = segment
            let curve = segment.cubic
            var first = curve.control1 - curve.start
            var second = curve.control2 - curve.end
            let firstLength = first.magnitude
            let secondLength = second.magnitude
            let chordVector = curve.end - curve.start
            let chord = chordVector.magnitude
            if firstLength > 1e-9, secondLength > 1e-9, chord > 1e-9 {
                if let triangle = ContourRefiner.handleTriangle(
                    start: curve.start,
                    startDirection: first / firstLength,
                    end: curve.end,
                    endDirection: second / secondLength
                ) {
                    if firstLength > triangle.0 { first = first * (triangle.0 / firstLength) }
                    if secondLength > triangle.1 { second = second * (triangle.1 / secondLength) }
                }
                let chordDirection = chordVector / chord
                let reach = first.dot(chordDirection) - second.dot(chordDirection)
                let limit = chord * handleReachMaximum
                if reach > limit {
                    first = first * (limit / reach)
                    second = second * (limit / reach)
                }
            }
            result.cubic.control1 = curve.start + first
            result.cubic.control2 = curve.end + second
            return result
        })
    }

    static func evenSegment(_ curve: CubicBezier) -> (Point2D, Point2D) {
        let firstVector = curve.control1 - curve.start
        let secondVector = curve.control2 - curve.end
        let firstLength = firstVector.magnitude
        let secondLength = secondVector.magnitude
        let chord = curve.start.distance(to: curve.end)
        guard chord >= minimumChord,
              firstLength >= minimumHandle || secondLength >= minimumHandle,
              let firstDirection = firstVector.normalized(epsilon: 1e-9),
              let secondDirection = secondVector.normalized(epsilon: 1e-9)
        else { return (curve.control1, curve.control2) }
        let spans = ContourRefiner.handleSpans(
            start: curve.start,
            startDirection: firstDirection,
            end: curve.end,
            endDirection: secondDirection
        )
        func ratio(_ first: Double, _ second: Double) -> Double {
            let normalized: (Double, Double)
            if let spans { normalized = (first / spans.0, second / spans.1) }
            else { normalized = (first, second) }
            return max(normalized.0, normalized.1) / min(normalized.0, normalized.1)
        }
        guard ratio(firstLength, secondLength) >= ratioTrigger else {
            return (curve.control1, curve.control2)
        }
        let original = sample(curve)
        let budget = max(maximumDeviationAbsolute, chord * maximumDeviationFraction)
        let chordVector = curve.end - curve.start
        let chordDirection = chordVector / chord
        let reachLimit = chord * handleReachMaximum
        let low = max(min(firstLength, secondLength) * 0.5, minimumHandle)
        let high = max(firstLength, secondLength) * 1.3
        guard high > low else { return (curve.control1, curve.control2) }
        let triangle = ContourRefiner.handleTriangle(
            start: curve.start,
            startDirection: firstDirection,
            end: curve.end,
            endDirection: secondDirection
        )
        var best = (firstLength, secondLength)
        var bestRatio = ratio(firstLength, secondLength)
        var bestDeviation = 0.0
        for firstStep in 0...grid {
            let first = low + (high - low) * Double(firstStep) / Double(grid)
            for secondStep in 0...grid {
                let second = low + (high - low) * Double(secondStep) / Double(grid)
                if first * firstDirection.dot(chordDirection)
                    - second * secondDirection.dot(chordDirection) > reachLimit
                { continue }
                if let triangle, first > triangle.0 || second > triangle.1 { continue }
                let candidate = CubicBezier(
                    start: curve.start,
                    control1: curve.start + firstDirection * first,
                    control2: curve.end + secondDirection * second,
                    end: curve.end
                )
                let values = sample(candidate)
                let deviation = zip(original, values).reduce(0.0) {
                    max($0, $1.0.distance(to: $1.1))
                }
                guard deviation <= budget else { continue }
                let candidateRatio = ratio(first, second)
                if candidateRatio < bestRatio - 1e-6
                    || (candidateRatio <= bestRatio + 1e-6 && deviation < bestDeviation)
                {
                    best = (first, second)
                    bestRatio = candidateRatio
                    bestDeviation = deviation
                }
            }
        }
        return (
            curve.start + firstDirection * best.0,
            curve.end + secondDirection * best.1
        )
    }

    private static func sample(_ curve: CubicBezier) -> [Point2D] {
        (0...samples).map { curve.point(at: Double($0) / Double(samples)) }
    }
}
