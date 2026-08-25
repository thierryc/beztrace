// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum ContourFitter {
    static func fitClosed(smoothed: [Point2D], accuracy: Double) -> FittedContour {
        guard let first = smoothed.first else {
            return FittedContour(segments: [], isLine: [], jointKinds: [])
        }
        let segments = fitOpenSamples(smoothed + [first], accuracy: accuracy)
        return FittedContour(
            segments: segments,
            isLine: Array(repeating: false, count: segments.count),
            jointKinds: Array(repeating: .fitterJoint, count: segments.count)
        )
    }

    static func fitInitial(plan: ContourPlan, accuracy: Double) -> FittedContour {
        var result = fitSections(plan: plan, accuracy: accuracy)
        result = FittingFinish.mergeCollinearLines(result)
        result = FittingFinish.collapseCornerSlivers(result)
        result = FittingFinish.collapseMicroLines(result)
        result = FittingFinish.tameShortCubicHandles(result)
        result = FittingFinish.smoothJoins(result)
        return result
    }

    static func fitSections(plan: ContourPlan, accuracy: Double) -> FittedContour {
        let sampleCount = plan.smoothed.count
        var segments: [CubicBezier] = []
        var lineFlags: [Bool] = []
        var jointKinds: [SplitKind] = []

        for splitIndex in plan.splits.indices {
            let startSplit = plan.splits[splitIndex]
            let endSplit = plan.splits[(splitIndex + 1) % plan.splits.count]
            let distance = positiveModulo(endSplit.index + sampleCount - startSplit.index, sampleCount)
            let length = distance == 0 ? sampleCount : distance
            let samples = (0...length).map {
                plan.smoothed[(startSplit.index + $0) % sampleCount]
            }
            let isPlannedLine = plan.lineSections.contains {
                $0.start == startSplit.index && $0.end == endSplit.index
            }
            let isShortStraight = samples.count <= FittingConstants.shortStraightMaximumSamples
                && chordDeviation(samples) <= FittingConstants.shortStraightMaximumDeviation

            if isPlannedLine || isShortStraight || samples.count < 3 {
                segments.append(lineCubic(from: samples[0], to: samples[samples.count - 1]))
                lineFlags.append(true)
                jointKinds.append(startSplit.kind)
                continue
            }

            let startTangent = constrainedEndTangent(
                samples: samples,
                kind: startSplit.kind,
                atStart: true
            )
            let endTangent = constrainedEndTangent(
                samples: samples,
                kind: endSplit.kind,
                atStart: false
            )
            let tolerance = accuracy * FittingConstants.constrainedFitToleranceFactor
            let single = constrainedCubicFit(
                samples: samples,
                startTangent: startTangent,
                endTangent: endTangent
            )
            if single.maximumError <= tolerance {
                segments.append(single.curve)
                lineFlags.append(false)
                jointKinds.append(startSplit.kind)
            } else if let pair = fitSplitAtInflection(
                samples: samples,
                startTangent: startTangent,
                endTangent: endTangent,
                tolerance: tolerance
            ) {
                for index in pair.segments.indices {
                    segments.append(pair.segments[index])
                    lineFlags.append(pair.isLine[index])
                    jointKinds.append(index == 0 ? startSplit.kind : .fitterJoint)
                }
            } else {
                let fitted = fitOpenSamples(samples, accuracy: accuracy)
                for (index, curve) in fitted.enumerated() {
                    segments.append(curve)
                    // The pinned fallback records every created span as a
                    // fitter cubic, including a degenerate straight span.
                    lineFlags.append(false)
                    jointKinds.append(index == 0 ? startSplit.kind : .fitterJoint)
                }
            }
        }
        return FittedContour(segments: segments, isLine: lineFlags, jointKinds: jointKinds)
    }

    static func constrainedEndTangent(
        samples: [Point2D],
        kind: SplitKind,
        atStart: Bool
    ) -> Vector2D {
        let count = samples.count
        let window = min(6, count - 1)
        let measured = atStart
            ? samples[window] - samples[0]
            : samples[count - 1 - window] - samples[count - 1]
        let raw = measured.magnitude < 1e-9
            ? Vector2D(dx: 1, dy: 0)
            : measured.normalized()!

        switch kind {
        case .extremumX:
            return Vector2D(dx: 0, dy: numericSign(raw.dy))
        case .extremumY:
            return Vector2D(dx: numericSign(raw.dx), dy: 0)
        default:
            let corner = kind == .corner
            let band = corner
                ? FittingConstants.cornerAxisSnapDegrees
                : FittingConstants.freeDirectionAxisSnapDegrees
            func nearHorizontal(_ direction: Vector2D, degrees: Double) -> Bool {
                abs(direction.dx) > abs(direction.dy)
                    && abs(direction.dy) <= abs(direction.dx) * tan(degrees * .pi / 180)
            }
            func nearVertical(_ direction: Vector2D, degrees: Double) -> Bool {
                abs(direction.dy) > abs(direction.dx)
                    && abs(direction.dx) <= abs(direction.dy) * tan(degrees * .pi / 180)
            }
            func beyondRoundingZone() -> Vector2D? {
                let skip = min(PlanningConstants.splitSnapSamples, max(count - 8, 0) / 2)
                let beyondWindow = min(6, max(count - (1 + skip), 0))
                guard skip != 0, beyondWindow >= 3 else { return nil }
                let direction = atStart
                    ? samples[skip + beyondWindow] - samples[skip]
                    : samples[count - 1 - skip - beyondWindow] - samples[count - 1 - skip]
                return direction.magnitude > 1e-9 ? direction.normalized() : nil
            }

            if nearHorizontal(raw, degrees: band) {
                return Vector2D(dx: numericSign(raw.dx), dy: 0)
            }
            if nearVertical(raw, degrees: band) {
                return Vector2D(dx: 0, dy: numericSign(raw.dy))
            }
            if corner && (
                nearHorizontal(raw, degrees: FittingConstants.freeDirectionAxisSnapDegrees)
                    || nearVertical(raw, degrees: FittingConstants.freeDirectionAxisSnapDegrees)
            ) {
                let direction = beyondRoundingZone() ?? raw
                if nearHorizontal(direction, degrees: FittingConstants.cornerAxisSnapDegrees) {
                    return Vector2D(dx: numericSign(direction.dx), dy: 0)
                }
                if nearVertical(direction, degrees: FittingConstants.cornerAxisSnapDegrees) {
                    return Vector2D(dx: 0, dy: numericSign(direction.dy))
                }
                return direction
            }
            return raw
        }
    }

    static func constrainedCubicFit(
        samples: [Point2D],
        startTangent: Vector2D,
        endTangent: Vector2D
    ) -> CubicFitResult {
        precondition(!samples.isEmpty)
        let start = samples[0]
        let end = samples[samples.count - 1]
        let chord = start.distance(to: end)

        var parameters = [0.0]
        parameters.reserveCapacity(samples.count)
        var accumulated = 0.0
        for index in 1..<samples.count {
            accumulated += samples[index].distance(to: samples[index - 1])
            parameters.append(accumulated)
        }
        let total = max(accumulated, 1e-12)
        for index in parameters.indices { parameters[index] /= total }

        func point(alpha: Double, beta: Double, parameter: Double) -> Point2D {
            let inverse = 1 - parameter
            let b0 = inverse * inverse * inverse
            let b1 = 3 * inverse * inverse * parameter
            let b2 = 3 * inverse * parameter * parameter
            let b3 = parameter * parameter * parameter
            let control1 = start + startTangent * alpha
            let control2 = end + endTangent * beta
            return Point2D(
                x: b0 * start.x + b1 * control1.x + b2 * control2.x + b3 * end.x,
                y: b0 * start.y + b1 * control1.y + b2 * control2.y + b3 * end.y
            )
        }

        var alpha = chord / 3
        var beta = chord / 3
        for _ in 0..<3 {
            var xx = 0.0
            var xy = 0.0
            var yy = 0.0
            var xd = 0.0
            var yd = 0.0
            for (index, parameter) in parameters.enumerated() {
                let inverse = 1 - parameter
                let b1 = 3 * inverse * inverse * parameter
                let b2 = 3 * inverse * parameter * parameter
                let base = Point2D(
                    x: (inverse * inverse * inverse + b1) * start.x
                        + (b2 + parameter * parameter * parameter) * end.x,
                    y: (inverse * inverse * inverse + b1) * start.y
                        + (b2 + parameter * parameter * parameter) * end.y
                )
                let first = startTangent * b1
                let second = endTangent * b2
                let difference = samples[index] - base
                xx += first.dot(first)
                xy += first.dot(second)
                yy += second.dot(second)
                xd += first.dot(difference)
                yd += second.dot(difference)
            }
            let determinant = xx * yy - xy * xy
            if abs(determinant) > 1e-12 {
                alpha = (xd * yy - yd * xy) / determinant
                beta = (xx * yd - xy * xd) / determinant
            }
            let minimumLength = max(chord * 0.02, 1e-6)
            let maximumLength = chord * 1.2
            alpha = min(max(alpha, minimumLength), maximumLength)
            beta = min(max(beta, minimumLength), maximumLength)

            for index in parameters.indices {
                let parameter = parameters[index]
                let curvePoint = point(alpha: alpha, beta: beta, parameter: parameter)
                let epsilon = 1e-4
                let after = point(
                    alpha: alpha,
                    beta: beta,
                    parameter: min(parameter + epsilon, 1)
                )
                let before = point(
                    alpha: alpha,
                    beta: beta,
                    parameter: max(parameter - epsilon, 0)
                )
                let derivative = (after - before) / (2 * epsilon)
                let difference = curvePoint - samples[index]
                let denominator = derivative.dot(derivative)
                if denominator > 1e-12 {
                    parameters[index] = min(
                        max(parameter - difference.dot(derivative) / denominator, 0),
                        1
                    )
                }
            }
            parameters[0] = 0
            parameters[parameters.count - 1] = 1
        }

        let curve = CubicBezier(
            start: start,
            control1: start + startTangent * alpha,
            control2: end + endTangent * beta,
            end: end
        )
        let error = zip(parameters, samples).reduce(0) { maximum, pair in
            max(maximum, curve.point(at: pair.0).distance(to: pair.1))
        }
        return CubicFitResult(curve: curve, maximumError: error)
    }

    static func fitOpenSamples(_ samples: [Point2D], accuracy: Double) -> [CubicBezier] {
        guard samples.count >= 3, samples[0].distance(to: samples[samples.count - 1]) >= 1.5 else {
            return [lineCubic(from: samples[0], to: samples[samples.count - 1])]
        }
        let count = samples.count
        var cumulative = [0.0]
        cumulative.reserveCapacity(count)
        var accumulated = 0.0
        for index in 1..<count {
            accumulated += samples[index].distance(to: samples[index - 1])
            cumulative.append(accumulated)
        }
        let total = max(accumulated, 1e-12)

        func tangent(at index: Int) -> Vector2D {
            let first = max(index - 1, 0)
            let last = min(index + 1, count - 1)
            let direction = samples[last] - samples[first]
            return direction.magnitude < 1e-9
                ? Vector2D(dx: 1, dy: 0)
                : direction.normalized()!
        }
        func fitSpan(_ first: Int, _ last: Int) -> CubicFitResult {
            let span = Array(samples[first...last])
            if span.count <= FittingConstants.shortStraightMaximumSamples
                && chordDeviation(span) <= FittingConstants.shortStraightMaximumDeviation
            {
                return CubicFitResult(
                    curve: lineCubic(from: span[0], to: span[span.count - 1]),
                    maximumError: 0
                )
            }
            return constrainedCubicFit(
                samples: span,
                startTangent: tangent(at: first),
                endTangent: -tangent(at: last)
            )
        }

        let maximumSegments = max(min(FittingConstants.openFitMaximumSegments, count / 2), 1)
        var best: (error: Double, segments: [CubicBezier])?
        for segmentCount in 1...maximumSegments {
            var boundaries = [0]
            boundaries.reserveCapacity(segmentCount + 1)
            var cursor = 0
            if segmentCount > 1 {
                for subdivision in 1..<segmentCount {
                    let target = total * Double(subdivision) / Double(segmentCount)
                    while cursor + 1 < count - 1 && cumulative[cursor + 1] < target {
                        cursor += 1
                    }
                    let candidate: Int
                    if cursor + 1 < count - 1
                        && abs(cumulative[cursor + 1] - target) < abs(target - cumulative[cursor])
                    {
                        candidate = cursor + 1
                    } else {
                        candidate = cursor
                    }
                    let previous = boundaries[boundaries.count - 1]
                    boundaries.append(
                        min(max(candidate, previous + 1), count - 1 - (segmentCount - subdivision))
                    )
                }
            }
            boundaries.append(count - 1)
            guard zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }) else { break }

            var segments: [CubicBezier] = []
            var worst = 0.0
            for (first, last) in zip(boundaries, boundaries.dropFirst()) {
                let fitted = fitSpan(first, last)
                worst = max(worst, fitted.maximumError)
                segments.append(fitted.curve)
            }
            if best == nil || worst < best!.error { best = (worst, segments) }
            if worst <= accuracy { break }
        }
        return best!.segments
    }

    private static func fitSplitAtInflection(
        samples: [Point2D],
        startTangent: Vector2D,
        endTangent: Vector2D,
        tolerance: Double
    ) -> (segments: [CubicBezier], isLine: [Bool])? {
        let count = samples.count
        guard count >= 24 else { return nil }
        let radius = 6
        let curvature = samples.indices.map { index -> Double in
            let low = max(index - radius, 0)
            let high = min(index + radius, count - 1)
            let incoming = samples[index] - samples[low]
            let outgoing = samples[high] - samples[index]
            return atan2(incoming.cross(outgoing), incoming.dot(outgoing))
        }
        let margin = 8
        var best: (index: Int, strength: Double)?
        for index in margin..<(count - margin) where curvature[index] * curvature[index + 1] < 0 {
            let left = curvature[...index].reduce(0) { max($0, abs($1)) }
            let right = curvature[(index + 1)...].reduce(0) { max($0, abs($1)) }
            let strength = min(left, right)
            if best == nil || strength > best!.strength { best = (index, strength) }
        }
        guard let split = best?.index else { return nil }
        let window = min(6, split, count - 1 - split)
        guard let direction = (samples[split + window] - samples[split - window]).normalized() else {
            return nil
        }

        let minimumPiece = 18
        if split < minimumPiece
            && chordDeviation(Array(samples[...split])) <= FittingConstants.shortStraightMaximumDeviation,
           let lineDirection = (samples[split] - samples[0]).normalized()
        {
            let right = constrainedCubicFit(
                samples: Array(samples[split...]),
                startTangent: lineDirection,
                endTangent: endTangent
            )
            if right.maximumError <= tolerance {
                return ([lineCubic(from: samples[0], to: samples[split]), right.curve], [true, false])
            }
        }
        if count - 1 - split < minimumPiece
            && chordDeviation(Array(samples[split...])) <= FittingConstants.shortStraightMaximumDeviation,
           let lineDirection = (samples[count - 1] - samples[split]).normalized()
        {
            let left = constrainedCubicFit(
                samples: Array(samples[...split]),
                startTangent: startTangent,
                endTangent: -lineDirection
            )
            if left.maximumError <= tolerance {
                return ([left.curve, lineCubic(from: samples[split], to: samples[count - 1])], [false, true])
            }
        }

        let left = constrainedCubicFit(
            samples: Array(samples[...split]),
            startTangent: startTangent,
            endTangent: -direction
        )
        let right = constrainedCubicFit(
            samples: Array(samples[split...]),
            startTangent: direction,
            endTangent: endTangent
        )
        guard max(left.maximumError, right.maximumError) <= tolerance else { return nil }
        return ([left.curve, right.curve], [false, false])
    }
}
