// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

extension ContourPlanner {
    private static let arcChainMaximumStepDegrees = 15.0
    private static let arcChainNeutralStepDegrees = 1.5
    private static let arcChainMinimumTotalDegrees = 2.5
    private static let arcChainMinimumRuns = 3

    static func detectStraightRuns(
        smoothed: [Point2D],
        turns: [Double],
        corners: [Int]
    ) -> [LineSection] {
        let count = smoothed.count
        func nearCorner(_ index: Int) -> Bool {
            corners.contains { corner in
                positiveModulo(index + count - corner, count) <= PlanningConstants.splitSnapSamples
                    || positiveModulo(corner + count - index, count) <= PlanningConstants.splitSnapSamples
            }
        }
        let origin: Int
        if let first = corners.first {
            origin = first
        } else {
            var best = 0
            var bestDeviation = -Double.infinity
            for index in 0..<count {
                let points = (0..<9).map { smoothed[positiveModulo(index + $0 - 4, count)] }
                let deviation = chordDeviation(points)
                if deviation >= bestDeviation {
                    best = index
                    bestDeviation = deviation
                }
            }
            origin = best
        }
        func onCornerRounding(_ index: Int) -> Bool {
            corners.contains { corner in
                let distance = positiveModulo(index + count - corner, count)
                return min(distance, count - distance) <= 3
            }
        }

        var runs: [LineSection] = []
        var index = origin
        var consumed = 0
        while consumed < count {
            if onCornerRounding(index % count) {
                index += 1
                consumed += 1
                continue
            }
            let floor = nearCorner(index % count)
                ? PlanningConstants.cornerFlatDeviationFloor
                : PlanningConstants.straightDeviationFloor
            var end = index + 1
            var buffer = [smoothed[index % count], smoothed[(index + 1) % count]]
            while end - index < count - 1 {
                buffer.append(smoothed[(end + 1) % count])
                let chord = buffer[0].distance(to: buffer[buffer.count - 1])
                let allowed = max(floor, chord * PlanningConstants.straightDeviationSlope)
                if chordDeviation(buffer) > allowed {
                    buffer.removeLast()
                    break
                }
                end += 1
            }
            let chord = smoothed[index % count].distance(to: smoothed[end % count])
            let length = end - index
            if length >= 2 {
                let minimumChord = nearCorner(index % count) && nearCorner(end % count)
                    ? PlanningConstants.straightMinimumChordAtCorner
                    : PlanningConstants.straightMinimumChord
                if chord >= minimumChord {
                    func relaxedOK(_ points: [Point2D]) -> Bool {
                        let candidateChord = points[0].distance(to: points[points.count - 1])
                        return chordDeviation(points) <= max(
                            PlanningConstants.cornerFlatDeviationFloor,
                            candidateChord * PlanningConstants.straightDeviationSlope
                        )
                    }
                    var extendedStart = index
                    var extended = buffer
                    while index - extendedStart < PlanningConstants.runExtendMaximumSamples,
                          end - extendedStart < count - 1
                    {
                        let previous = positiveModulo(extendedStart - 1, count)
                        let candidate = [smoothed[previous]] + extended
                        guard relaxedOK(candidate) else { break }
                        extended = candidate
                        extendedStart -= 1
                    }
                    var extendedEnd = end
                    while extendedEnd - end < PlanningConstants.runExtendMaximumSamples,
                          extendedEnd - extendedStart < count - 1
                    {
                        let next = positiveModulo(extendedEnd + 1, count)
                        let candidate = extended + [smoothed[next]]
                        guard relaxedOK(candidate) else { break }
                        extended = candidate
                        extendedEnd += 1
                    }
                    let startIndex = positiveModulo(extendedStart, count)
                    let endIndex = positiveModulo(extendedEnd, count)
                    let finalStart = startIndex != index % count && nearCorner(startIndex)
                        ? startIndex : index % count
                    let finalEnd = endIndex != end % count && nearCorner(endIndex)
                        ? endIndex : end % count
                    runs.append(LineSection(start: finalStart, end: finalEnd))
                }
            }
            consumed += max(end - index, 1)
            index = max(end, index + 1)
        }
        return keepAnchoredRuns(runs, smoothed: smoothed, turns: turns, corners: corners)
    }

    private static func keepAnchoredRuns(
        _ runs: [LineSection],
        smoothed: [Point2D],
        turns: [Double],
        corners: [Int]
    ) -> [LineSection] {
        let count = smoothed.count
        func cyclicDistance(_ first: Int, _ second: Int) -> Int {
            let distance = positiveModulo(first + count - second, count)
            return min(distance, count - distance)
        }
        let maximumOffAxis = tan(PlanningConstants.runAxisMaximumDegrees * .pi / 180)
        let bounds = Bounds(points: smoothed)!
        let diagonal = hypot(bounds.width, bounds.height)
        func flank(from: Int, backwards: Bool) -> Double {
            var result = 0.0
            for offset in 1...PlanningConstants.arcFlatFlankWindow {
                let index = backwards
                    ? positiveModulo(from - offset, count)
                    : (from + offset) % count
                result += turns[index]
            }
            return result * 180 / .pi
        }
        var keep = runs.map { run -> Bool in
            let first = smoothed[run.start]
            let second = smoothed[run.end]
            let dx = abs(second.x - first.x)
            let dy = abs(second.y - first.y)
            let directionOK = (dx > dy && dy <= dx * maximumOffAxis)
                || (dy > dx && dx <= dy * maximumOffAxis)
            let cornerAnchored = corners.contains { corner in
                cyclicDistance(run.start, corner) <= 2 * PlanningConstants.splitSnapSamples
                    || cyclicDistance(run.end, corner) <= 2 * PlanningConstants.splitSnapSamples
            }
            if !cornerAnchored {
                let before = flank(from: run.start, backwards: true)
                let after = flank(from: run.end, backwards: false)
                let chord = first.distance(to: second)
                if numericSign(before) == numericSign(after),
                   abs(before) >= PlanningConstants.arcFlatMinimumFlankDegrees,
                   abs(after) >= PlanningConstants.arcFlatMinimumFlankDegrees,
                   abs(before) <= PlanningConstants.arcFlatMaximumFlankDegrees,
                   abs(after) <= PlanningConstants.arcFlatMaximumFlankDegrees,
                   chord < diagonal * PlanningConstants.arcFlatMaximumChordFraction
                {
                    return false
                }
            }
            return directionOK || cornerAnchored
        }
        while true {
            var changed = false
            for index in runs.indices where !keep[index] {
                let run = runs[index]
                let linked = runs.indices.contains { otherIndex in
                    guard otherIndex != index, keep[otherIndex] else { return false }
                    let other = runs[otherIndex]
                    return [
                        cyclicDistance(run.start, other.start),
                        cyclicDistance(run.start, other.end),
                        cyclicDistance(run.end, other.start),
                        cyclicDistance(run.end, other.end),
                    ].contains { $0 <= PlanningConstants.splitSnapSamples }
                }
                if linked { keep[index] = true; changed = true }
            }
            if !changed { break }
        }
        return zip(runs, keep).compactMap { $1 ? $0 : nil }
    }

    static func dropArcChainRuns(
        _ runs: [LineSection],
        smoothed: [Point2D]
    ) -> [LineSection] {
        let runCount = runs.count
        guard runCount >= arcChainMinimumRuns else { return runs }
        let sampleCount = smoothed.count
        func direction(_ run: LineSection) -> Double {
            let delta = smoothed[run.end] - smoothed[run.start]
            return atan2(delta.dy, delta.dx)
        }
        func runLength(_ run: LineSection) -> Int {
            positiveModulo(run.end + sampleCount - run.start, sampleCount)
        }
        func gap(_ first: LineSection, _ second: LineSection) -> Int {
            positiveModulo(second.start + sampleCount - first.end, sampleCount)
        }
        let steps: [Double?] = runs.indices.map { index in
            let first = runs[index]
            let second = runs[(index + 1) % runCount]
            var difference = direction(second) - direction(first)
            while difference > .pi { difference -= 2 * .pi }
            while difference < -.pi { difference += 2 * .pi }
            let close = gap(first, second) <= min(runLength(first), runLength(second)) * 3 / 2
            return close && abs(difference) <= arcChainMaximumStepDegrees * .pi / 180
                ? difference : nil
        }
        let neutral = arcChainNeutralStepDegrees * .pi / 180
        var drop = Array(repeating: false, count: runCount)
        var index = 0
        while index < runCount {
            guard steps[index] != nil else { index += 1; continue }
            var sign = 0.0
            var total = 0.0
            var count = 1
            var end = index
            while count <= runCount {
                guard let difference = steps[end % runCount] else { break }
                if abs(difference) >= neutral {
                    if sign != 0, numericSign(difference) != sign { break }
                    sign = numericSign(difference)
                }
                total += difference
                count += 1
                end += 1
            }
            let qualifies = count >= arcChainMinimumRuns
                && abs(total) >= arcChainMinimumTotalDegrees * .pi / 180
            if qualifies {
                for runIndex in index..<(index + count) { drop[runIndex % runCount] = true }
            }
            index = max(end + 1, index + 1)
        }
        return runs.indices.compactMap { drop[$0] ? nil : runs[$0] }
    }
}
