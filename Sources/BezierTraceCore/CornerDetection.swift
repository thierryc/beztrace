// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

extension ContourPlanner {
    private static let bracketMinimumTotalTurnDegrees = 45.0
    private static let bracketMaximumZoneSamples = 140
    private static let bracketCandidateMergeGap = 12
    private static let bracketMaximumRadiusPixels = 18.0

    static func countTurnSpikes(_ turns: [Double], cornerDegrees: Double) -> Int {
        let centralMinimum = cornerDegrees * .pi / 180
        let mergeGap = 2
        var clusters = 0
        var last: Int?
        var first: Int?
        for index in turns.indices {
            let central = turns[positiveModulo(index - 1, turns.count)]
                + turns[index]
                + turns[(index + 1) % turns.count]
            guard abs(central) >= centralMinimum else { continue }
            if first == nil { first = index }
            if last == nil || index - last! > mergeGap { clusters += 1 }
            last = index
        }
        if clusters >= 2, let first, let last,
           positiveModulo(first + turns.count - last, turns.count) <= mergeGap
        {
            clusters -= 1
        }
        return clusters
    }

    static func detectCorners(
        turns: [Double],
        smoothed: [Point2D],
        cornerDegrees: Double,
        sigma: Double,
        cornerSmear: Bool
    ) -> [Int] {
        let count = turns.count
        let centralMinimum = cornerDegrees * .pi / 180
        let totalMinimum = PlanningConstants.cornerMinimumTotalTurnDegrees * .pi / 180
        let centralHalf = max(1, Int((sigma / 1.2).rounded()))
        let half = max(PlanningConstants.cornerWindow, Int(ceil(3 * sigma)))

        func span(_ index: Int, _ radius: Int) -> Double {
            var result = 0.0
            for offset in 0..<(2 * radius + 1) {
                result += turns[positiveModulo(index + offset - radius, count)]
            }
            return result
        }
        func flank(_ index: Int, backwards: Bool) -> Double {
            var result = 0.0
            for offset in (half + 1)...(2 * half) {
                result += turns[backwards
                    ? positiveModulo(index - offset, count)
                    : (index + offset) % count]
            }
            return result
        }

        var candidates: [Int] = []
        for index in 0..<count {
            let central = span(index, centralHalf)
            let window = span(index, half)
            let cusp = cornerSmear
                && abs(window) >= PlanningConstants.cornerCuspTurnDegrees * .pi / 180
            let quiet = PlanningConstants.cornerShallowFlankMaximumDegrees * .pi / 180
            let shallowDesigned = abs(window)
                >= PlanningConstants.cornerShallowMinimumTotalTurnDegrees * .pi / 180
                && abs(flank(index, backwards: true)) <= quiet
                && abs(flank(index, backwards: false)) <= quiet
            if abs(central) >= centralMinimum,
               abs(window) >= totalMinimum || shallowDesigned,
               cusp || abs(central) >= PlanningConstants.cornerConcentration * abs(window)
            {
                candidates.append(index)
            }
        }

        var keep: [Int] = []
        for index in candidates {
            if let last = keep.last,
               positiveModulo(index + count - last, count) <= PlanningConstants.cornerWindow
            {
                if abs(turns[index]) > abs(turns[last]) { keep[keep.count - 1] = index }
            } else {
                keep.append(index)
            }
        }
        if keep.count >= 2 {
            let first = keep[0]
            let last = keep[keep.count - 1]
            if positiveModulo(first + count - last, count) <= PlanningConstants.cornerWindow {
                if abs(turns[first]) >= abs(turns[last]) {
                    keep.removeLast()
                } else {
                    keep.removeFirst()
                }
            }
        }
        return keep
    }

    static func detectRoundCornerBrackets(
        turns: [Double],
        smoothed: [Point2D],
        corners: [Int],
        cornerDegrees: Double,
        sigma: Double,
        raster: RasterTarget?
    ) -> [StructuralSplit] {
        let count = turns.count
        let centralMinimum = cornerDegrees * .pi / 180
        let centralHalf = max(1, Int((sigma / 1.2).rounded()))
        let half = max(PlanningConstants.cornerWindow, Int(ceil(3 * sigma)))
        func span(_ index: Int, _ radius: Int) -> Double {
            var result = 0.0
            for offset in 0..<(2 * radius + 1) {
                result += turns[positiveModulo(index + offset - radius, count)]
            }
            return result
        }
        func cyclicDistance(_ first: Int, _ second: Int) -> Int {
            let distance = positiveModulo(first + count - second, count)
            return min(distance, count - distance)
        }

        let candidates = (0..<count).filter { index in
            abs(span(index, centralHalf)) >= centralMinimum
                && corners.allSatisfy { cyclicDistance(index, $0) > 2 * half }
        }
        guard !candidates.isEmpty else { return [] }

        let net = turns.reduce(0, +)
        var result: [StructuralSplit] = []
        var zoneIndex = 0
        while zoneIndex < candidates.count {
            let start = candidates[zoneIndex]
            var end = start
            var nextZoneIndex = zoneIndex + 1
            while nextZoneIndex < candidates.count,
                  positiveModulo(candidates[nextZoneIndex] + count - end, count)
                    <= bracketCandidateMergeGap
            {
                end = candidates[nextZoneIndex]
                nextZoneIndex += 1
            }
            let zoneLength = positiveModulo(end + count - start, count)
            var total = 0.0
            var sample = positiveModulo(start - half, count)
            let steps = min(zoneLength + 2 * half + 1, count)
            for _ in 0..<steps {
                total += turns[sample]
                sample = (sample + 1) % count
            }
            let totalSign = numericSign(total)
            let signOK = (zoneIndex..<nextZoneIndex).allSatisfy {
                numericSign(span(candidates[$0], centralHalf)) == totalSign
            }
            let arc = Double(zoneLength + 2 * half)
            let effectiveRadius = arc / max(abs(total), 1e-9)
            let wallOffset = 3 * half
            let firstWall = smoothed[positiveModulo(start - wallOffset, count)]
            let secondWall = smoothed[(end + wallOffset) % count]
            let midpoint = Point2D(
                x: (firstWall.x + secondWall.x) / 2,
                y: (firstWall.y + secondWall.y) / 2
            )
            let baseInk = raster.map { $0.coverage(x: midpoint.x, yUp: midpoint.y) >= 0.5 } ?? false
            let qualifies = zoneLength <= bracketMaximumZoneSamples
                && abs(total) >= bracketMinimumTotalTurnDegrees * .pi / 180
                && signOK
                && effectiveRadius <= bracketMaximumRadiusPixels
                && totalSign == numericSign(net)
                && baseInk
            if qualifies {
                var weightedOffset = 0.0
                var weightSum = 0.0
                for offset in 0...zoneLength {
                    let weight = abs(turns[(start + offset) % count])
                    weightedOffset += Double(offset) * weight
                    weightSum += weight
                }
                let apexOffset = Int((weightedOffset / max(weightSum, 1e-9)).rounded())
                result.append(StructuralSplit(index: (start + apexOffset) % count, kind: .corner))
            }
            zoneIndex = nextZoneIndex
        }
        return result
    }
}

@inline(__always)
func numericSign(_ value: Double) -> Double {
    value > 0 ? 1 : (value < 0 ? -1 : 0)
}
