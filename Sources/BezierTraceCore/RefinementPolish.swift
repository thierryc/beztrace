// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementPolish {
    private static let minimumBaseLoss = 0.02
    private static let minimumGain = 0.7
    private static let resultMaximum = 0.02
    private static let rescueBase = 0.10
    private static let rescueGain = 0.30
    private static let lopsidedRatio = 1.35
    private static let lopsidedGentleSlack = 0.040
    private static let lopsidedTightSlack = 0.012
    private static let lopsidedTurnReference = Double.pi / 2
    private static let lopsidedMaximumOptimumLoss = 0.06
    private static let lopsidedGrid = 28
    private static let slideTriggerHandle = 8.0
    private static let slideMaximumLineFraction = 0.5
    private static let slideGrid = 10
    private static let slideMaximumLossFactor = 1.02
    private static let slideMaximumAbsoluteLoss = 0.002
    private static let slideMinimumLine = 24.0
    private static let slideLateralSteps = 4
    private static let slideMaximumLateral = 3.0

    static func polish(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool,
        touched: [Point2D]
    ) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        let polylines = ContourRefiner.allPolylines(contour)
        for index in 0..<count where !contour.isLine[index] {
            let segment = contour.segments[index]
            let firstHandle = segment.control1 - segment.start
            let secondHandle = segment.control2 - segment.end
            guard let firstDirection = firstHandle.normalized(),
                  let secondDirection = secondHandle.normalized()
            else { continue }
            let band = ContourRefiner.collectBand(
                raster: raster,
                region: polylines[index],
                fixed: [
                    polylines[(index + count - 1) % count],
                    polylines[(index + 1) % count],
                ]
            )
            guard band.count >= 16 else { continue }
            let base = ContourRefiner.bandLoss(band, candidate: polylines[index], inkLeft: inkLeft)
            guard base >= minimumBaseLoss else { continue }
            let optimized = ContourRefiner.optimizeHandles(
                start: segment.start,
                startDirection: firstDirection,
                endDirection: secondDirection,
                end: segment.end,
                initial: (firstHandle.magnitude, secondHandle.magnitude),
                band: band,
                inkLeft: inkLeft
            )
            let nearTouched = touched.contains {
                $0.distance(to: segment.start) < 3 || $0.distance(to: segment.end) < 3
            }
            let accept = optimized.loss <= minimumGain * base && optimized.loss <= resultMaximum
                || nearTouched && base >= rescueBase && optimized.loss <= base * rescueGain
            if accept { contour.segments[index] = optimized.segment }
        }
        return contour
    }

    static func rebalance(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        let polylines = ContourRefiner.allPolylines(contour)
        for index in 0..<count where !contour.isLine[index] {
            let segment = contour.segments[index]
            let firstHandle = segment.control1 - segment.start
            let secondHandle = segment.control2 - segment.end
            let firstLength = firstHandle.magnitude
            let secondLength = secondHandle.magnitude
            if firstLength < 8, secondLength < 8 { continue }
            guard let firstDirection = firstHandle.normalized(),
                  let secondDirection = secondHandle.normalized()
            else { continue }
            let spans = ContourRefiner.handleSpans(
                start: segment.start,
                startDirection: firstDirection,
                end: segment.end,
                endDirection: secondDirection
            )
            func normalizedRatio(_ first: Double, _ second: Double) -> Double {
                let normalizedFirst = spans.map { first / $0.0 } ?? first
                let normalizedSecond = spans.map { second / $0.1 } ?? second
                return max(normalizedFirst, normalizedSecond) / max(min(normalizedFirst, normalizedSecond), 1e-300)
            }
            guard normalizedRatio(firstLength, secondLength) >= lopsidedRatio else { continue }
            let band = ContourRefiner.collectBand(
                raster: raster,
                region: polylines[index],
                fixed: [
                    polylines[(index + count - 1) % count],
                    polylines[(index + 1) % count],
                ]
            )
            guard band.count >= 16 else { continue }
            func evaluate(_ first: Double, _ second: Double) -> Double {
                let candidate = CubicBezier(
                    start: segment.start,
                    control1: segment.start + firstDirection * first,
                    control2: segment.end + secondDirection * second,
                    end: segment.end
                )
                return ContourRefiner.bandLoss(
                    band,
                    candidate: ContourRefiner.sampleCubic(candidate),
                    inkLeft: inkLeft
                )
            }
            let optimumLoss = evaluate(firstLength, secondLength)
            let turn = acos(min(max(-firstDirection.dot(secondDirection), -1), 1))
            let gentleness = min(max(1 - turn / lopsidedTurnReference, 0), 1)
            guard optimumLoss <= lopsidedMaximumOptimumLoss else { continue }
            let slack = lopsidedTightSlack + (lopsidedGentleSlack - lopsidedTightSlack) * gentleness
            let target = optimumLoss + slack
            let chord = segment.start.distance(to: segment.end)
            let low = max(chord * 0.02, 8)
            let high = chord * 1.1
            guard high > low else { continue }

            var best = (firstLength, secondLength)
            var bestRatio = normalizedRatio(firstLength, secondLength)
            var bestSpread = 0.0
            for firstIndex in 0...lopsidedGrid {
                let first = low + (high - low) * Double(firstIndex) / Double(lopsidedGrid)
                for secondIndex in 0...lopsidedGrid {
                    let second = low + (high - low) * Double(secondIndex) / Double(lopsidedGrid)
                    guard evaluate(first, second) <= target else { continue }
                    let ratio = normalizedRatio(first, second)
                    let spread = abs(first - firstLength) + abs(second - secondLength)
                    if ratio < bestRatio - 1e-6
                        || ratio <= bestRatio + 1e-6 && spread < bestSpread
                    {
                        best = (first, second)
                        bestRatio = ratio
                        bestSpread = spread
                    }
                }
            }
            contour.segments[index] = CubicBezier(
                start: segment.start,
                control1: segment.start + firstDirection * best.0,
                control2: segment.end + secondDirection * best.1,
                end: segment.end
            )
        }
        return contour
    }

    static func slide(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        guard count >= 3 else { return contour }
        for index in 0..<count where !contour.isLine[index] {
            let previous = (index + count - 1) % count
            if contour.isLine[previous],
               slideQualifies(contour.jointKinds[index]),
               contour.segments[index].start.distance(to: contour.segments[index].control1)
                    < slideTriggerHandle
            {
                trySlide(
                    contour: &contour,
                    raster: raster,
                    inkLeft: inkLeft,
                    lineIndex: previous,
                    curveIndex: index,
                    atStart: true
                )
            }
            let next = (index + 1) % count
            if contour.isLine[next],
               slideQualifies(contour.jointKinds[next]),
               contour.segments[index].end.distance(to: contour.segments[index].control2)
                    < slideTriggerHandle
            {
                trySlide(
                    contour: &contour,
                    raster: raster,
                    inkLeft: inkLeft,
                    lineIndex: next,
                    curveIndex: index,
                    atStart: false
                )
            }
        }
        return contour
    }

    private static func slideQualifies(_ kind: SplitKind) -> Bool {
        kind == .tangent || kind == .extremumX || kind == .extremumY
    }

    private static func trySlide(
        contour: inout FittedContour,
        raster: RasterTarget,
        inkLeft: Bool,
        lineIndex: Int,
        curveIndex: Int,
        atStart: Bool
    ) {
        let count = contour.segments.count
        let polylines = ContourRefiner.allPolylines(contour)
        let line = contour.segments[lineIndex]
        let curve = contour.segments[curveIndex]
        let far = atStart ? line.start : line.end
        let joint = atStart ? curve.start : curve.end
        let lineVector = joint - far
        let lineLength = lineVector.magnitude
        guard lineLength >= slideMinimumLine else { return }
        let direction = lineVector / lineLength
        let farTangent = atStart ? curve.control2 - curve.end : curve.control1 - curve.start
        guard let farDirection = farTangent.normalized() else { return }
        let farHandleLength = farTangent.magnitude
        let before = atStart ? (lineIndex + count - 1) % count : (curveIndex + count - 1) % count
        let after = atStart ? (curveIndex + 1) % count : (lineIndex + 1) % count
        let maximumDistance = lineLength * slideMaximumLineFraction
        let midpoint = joint + (-direction * maximumDistance)
        let region = atStart
            ? [midpoint, joint] + polylines[curveIndex]
            : polylines[curveIndex] + [joint, midpoint]
        let band = ContourRefiner.collectBand(
            raster: raster,
            region: region,
            fixed: [polylines[before], polylines[after]]
        )
        guard band.count >= 16 else { return }
        let basePolyline = atStart
            ? [far, joint] + polylines[curveIndex]
            : polylines[curveIndex] + [joint, far]
        let baseLoss = ContourRefiner.bandLoss(band, candidate: basePolyline, inkLeft: inkLeft)
        let limit = baseLoss * slideMaximumLossFactor + slideMaximumAbsoluteLoss
        let perpendicular = Vector2D(dx: -direction.dy, dy: direction.dx)
        var best: (loss: Double, point: Point2D, curve: CubicBezier)?
        for step in 1...slideGrid {
            let distance = maximumDistance * Double(step) / Double(slideGrid)
            for lateralStep in -slideLateralSteps...slideLateralSteps {
                let lateral = Double(lateralStep) * slideMaximumLateral / Double(slideLateralSteps)
                let point = joint + (-direction * distance) + perpendicular * lateral
                guard let lineDirection = (point - far).normalized() else { continue }
                let optimized: (segment: CubicBezier, loss: Double)
                if atStart {
                    optimized = ContourRefiner.optimizeHandles(
                        start: point,
                        startDirection: lineDirection,
                        endDirection: farDirection,
                        end: curve.end,
                        initial: (max(distance, slideTriggerHandle), farHandleLength),
                        band: band,
                        inkLeft: inkLeft,
                        prefix: [far, point]
                    )
                } else {
                    optimized = ContourRefiner.optimizeHandles(
                        start: curve.start,
                        startDirection: farDirection,
                        endDirection: -lineDirection,
                        end: point,
                        initial: (farHandleLength, max(distance, slideTriggerHandle)),
                        band: band,
                        inkLeft: inkLeft,
                        suffix: [point, far]
                    )
                }
                guard optimized.loss <= limit else { continue }
                let jointHandle = atStart
                    ? optimized.segment.start.distance(to: optimized.segment.control1)
                    : optimized.segment.end.distance(to: optimized.segment.control2)
                guard jointHandle >= slideTriggerHandle else { continue }
                if best == nil || optimized.loss < best!.loss {
                    best = (optimized.loss, point, optimized.segment)
                }
            }
        }
        guard let best else { return }
        contour.segments[lineIndex] = atStart
            ? lineCubic(from: far, to: best.point)
            : lineCubic(from: best.point, to: far)
        contour.segments[curveIndex] = best.curve
    }
}
