// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct TraceConfiguration: Equatable, Sendable {
    var targetHeight: Double
    var fitAccuracy: Double
    var smoothing: Double
    var cornerThresholdDegrees: Double
    var cornerSmear: Bool
    var softSource: Bool
    var refineRaster: Bool
    var grid: Int
    var structureGrid: Int
    var fixDirection: Bool
    var chamferSize: Double
    var chamferMinimumEdge: Double

    static let capturedDefaults = TraceConfiguration(
        targetHeight: 1088,
        fitAccuracy: 2,
        smoothing: 1,
        cornerThresholdDegrees: 12,
        cornerSmear: false,
        softSource: false,
        refineRaster: true,
        grid: 2,
        structureGrid: 0,
        fixDirection: true,
        chamferSize: 0,
        chamferMinimumEdge: 40
    )
}

enum SplitKind: Int, Equatable, Hashable, Sendable {
    case corner
    case tangent
    case extremumX
    case extremumY
    case inflection
    case fitterJoint

    var oracleName: String {
        switch self {
        case .corner: "Corner"
        case .tangent: "Tangent"
        case .extremumX: "ExtremumX"
        case .extremumY: "ExtremumY"
        case .inflection: "Inflection"
        case .fitterJoint: "FitterJoint"
        }
    }
}

struct StructuralSplit: Equatable, Sendable {
    let index: Int
    let kind: SplitKind
}

struct LineSection: Equatable, Sendable {
    let start: Int
    let end: Int
}

struct ContourPlan: Equatable, Sendable {
    let smoothed: [Point2D]
    let splits: [StructuralSplit]
    let lineSections: [LineSection]
}

enum ContourPlanningOutcome: Equatable, Sendable {
    case tooSmall
    case noSplits(smoothed: [Point2D])
    case plan(ContourPlan)
}

enum PlanningConstants {
    static let sampleSpacing = 1.0
    static let smoothSigma = 1.2
    static let maximumMeanAbsoluteTurn = 0.10
    static let minimumSamplesPerCorner = 30
    static let cornerWindow = 5
    static let cornerConcentration = 0.55
    static let cornerMinimumTotalTurnDegrees = 35.0
    static let cornerCuspTurnDegrees = 90.0
    static let cornerShallowMinimumTotalTurnDegrees = 18.0
    static let cornerShallowFlankMaximumDegrees = 5.0
    static let straightDeviationFloor = 0.15
    static let straightDeviationSlope = 0.005
    static let cornerFlatDeviationFloor = 0.45
    static let runExtendMaximumSamples = 20
    static let runAxisMaximumDegrees = 20.0
    static let straightMinimumChord = 30.0
    static let arcFlatFlankWindow = 24
    static let arcFlatMinimumFlankDegrees = 5.0
    static let arcFlatMaximumFlankDegrees = 30.0
    static let arcFlatMaximumChordFraction = 0.08
    static let straightMinimumChordAtCorner = 7.0
    static let splitSnapSamples = 8
    static let extremumProminence = 1.0
    static let extremumProminenceFraction = 0.012
    static let extremumStandoff = 5
    static let extremumRefineWindow = 14
    static let inflectionMaximumRadius = 150.0
    static let inflectionReach = 60
    static let inflectionMinimumSideTurnDegrees = 9.0
    static let inflectionStandoff = 12
    static let inflectionStandoffFraction = 1.0 / 64.0
    static let extremumSpacingFraction = 1.0 / 128.0
    static let inflectionBoundaryMargin = 12
    static let curvatureSigma = 3.0
}

enum ContourPlanner {
    static func plan(
        contour: SubpixelContour,
        configuration: TraceConfiguration,
        raster: RasterTarget?
    ) -> ContourPlanningOutcome {
        let resampled = resampleClosed(contour.points, spacing: PlanningConstants.sampleSpacing)
        let count = resampled.count
        guard count >= 12 else { return .tooSmall }

        var sigma = min(max(PlanningConstants.smoothSigma * configuration.smoothing, 0.05), 50)
        var smoothed = gaussianSmoothClosed(resampled, sigma: sigma)
        var turns = vertexTurns(smoothed)
        for _ in 0..<4 {
            let meanTurn = turns.reduce(0) { $0 + abs($1) } / Double(count)
            if meanTurn <= PlanningConstants.maximumMeanAbsoluteTurn,
               countTurnSpikes(turns, cornerDegrees: configuration.cornerThresholdDegrees)
                <= count / PlanningConstants.minimumSamplesPerCorner
            {
                break
            }
            sigma *= 1.8
            smoothed = gaussianSmoothClosed(resampled, sigma: sigma)
            turns = vertexTurns(smoothed)
        }

        let corners = detectCorners(
            turns: turns,
            smoothed: smoothed,
            cornerDegrees: configuration.cornerThresholdDegrees,
            sigma: sigma,
            cornerSmear: configuration.cornerSmear
        )
        let brackets = configuration.softSource ? [] : detectRoundCornerBrackets(
            turns: turns,
            smoothed: smoothed,
            corners: corners,
            cornerDegrees: configuration.cornerThresholdDegrees,
            sigma: sigma,
            raster: raster
        )
        var runs = detectStraightRuns(smoothed: smoothed, turns: turns, corners: corners)
        runs = dropArcChainRuns(runs, smoothed: smoothed)

        var splits = corners.map { StructuralSplit(index: $0, kind: .corner) }
        splits.append(contentsOf: brackets)
        var lineSections: [LineSection] = []
        for run in runs {
            let start = snapToExisting(run.start, splits: splits, count: count)
            let end = snapToExisting(run.end, splits: splits, count: count)
            guard start != end else { continue }
            for index in [start, end] where !splits.contains(where: { $0.index == index }) {
                splits.append(StructuralSplit(index: index, kind: .tangent))
            }
            lineSections.append(LineSection(start: start, end: end))
        }
        splits.sort { $0.index < $1.index }
        splits = deduplicatedSplits(splits)

        let base = splits
        let pieces: [(start: Int, length: Int)]
        if base.isEmpty {
            pieces = [(0, count), (count / 2, count)]
        } else {
            pieces = base.indices.map { index in
                let start = base[index].index
                let end = base[(index + 1) % base.count].index
                let length = positiveModulo(end + count - start, count)
                return (start, length == 0 ? count : length)
            }
        }
        var extra: [StructuralSplit] = []
        for piece in pieces {
            let isLine = lineSections.contains {
                $0.start == piece.start
                    && positiveModulo($0.end + count - $0.start, count) == piece.length % count
            }
            guard !isLine else { continue }
            extra.append(contentsOf: findExtrema(
                smoothed: smoothed,
                start: piece.start,
                length: piece.length
            ))
            extra.append(contentsOf: findInflections(
                turns: turns,
                smoothed: smoothed,
                start: piece.start,
                length: piece.length
            ))
        }
        for candidate in extra {
            let clear = !splits.contains { existing in
                let forward = positiveModulo(candidate.index + count - existing.index, count)
                let distance = min(forward, count - forward)
                let standoff: Int
                switch (candidate.kind, existing.kind) {
                case (.inflection, _):
                    standoff = max(
                        PlanningConstants.inflectionStandoff,
                        Int(Double(count) * PlanningConstants.inflectionStandoffFraction)
                    )
                case (_, .tangent):
                    standoff = PlanningConstants.splitSnapSamples
                case (.extremumX, .extremumX), (.extremumX, .extremumY),
                     (.extremumY, .extremumX), (.extremumY, .extremumY):
                    standoff = max(
                        PlanningConstants.extremumStandoff,
                        Int(Double(count) * PlanningConstants.extremumSpacingFraction)
                    )
                default:
                    standoff = PlanningConstants.extremumStandoff
                }
                return distance <= standoff
            }
            if clear { splits.append(candidate) }
        }
        splits.sort { $0.index < $1.index }

        if splits.isEmpty { return .noSplits(smoothed: smoothed) }
        return .plan(ContourPlan(smoothed: smoothed, splits: splits, lineSections: lineSections))
    }

    static func resampleClosed(_ points: [Point2D], spacing: Double) -> [Point2D] {
        guard !points.isEmpty else { return [] }
        var cumulative = [0.0]
        var total = 0.0
        for index in points.indices {
            total += points[index].distance(to: points[(index + 1) % points.count])
            cumulative.append(total)
        }
        guard total >= spacing * 4 else { return points }
        let count = Int((total / spacing).rounded())
        guard count > 0 else { return points }
        let step = total / Double(count)
        var result: [Point2D] = []
        result.reserveCapacity(count)
        var segment = 0
        for index in 0..<count {
            let target = Double(index) * step
            while segment + 1 < points.count, cumulative[segment + 1] < target {
                segment += 1
            }
            let length = cumulative[segment + 1] - cumulative[segment]
            let t = length > 1e-12 ? (target - cumulative[segment]) / length : 0
            result.append(points[segment].interpolated(to: points[(segment + 1) % points.count], t: t))
        }
        return result
    }

    static func gaussianSmoothClosed(_ points: [Point2D], sigma: Double) -> [Point2D] {
        guard !points.isEmpty else { return [] }
        let radius = Int(ceil(sigma * 3))
        var kernel = (-radius...radius).map { offset in
            exp(-pow(Double(offset), 2) / (2 * sigma * sigma))
        }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        return points.indices.map { index in
            var x = 0.0
            var y = 0.0
            for (kernelIndex, offset) in (-radius...radius).enumerated() {
                let point = points[positiveModulo(index + offset, points.count)]
                x += kernel[kernelIndex] * point.x
                y += kernel[kernelIndex] * point.y
            }
            return Point2D(x: x, y: y)
        }
    }

    static func vertexTurns(_ points: [Point2D]) -> [Double] {
        guard !points.isEmpty else { return [] }
        return points.indices.map { index in
            let previous = points[positiveModulo(index - 1, points.count)]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let incoming = current - previous
            let outgoing = next - current
            return atan2(incoming.cross(outgoing), incoming.dot(outgoing))
        }
    }

    static func chordDeviation(_ points: [Point2D]) -> Double {
        guard points.count > 2 else { return 0 }
        let first = points[0]
        let last = points[points.count - 1]
        let chord = last - first
        let length = chord.magnitude
        guard length > 1e-9 else {
            return points.map { $0.distance(to: first) }.max() ?? 0
        }
        return points.dropFirst().dropLast().map { point in
            abs((point - first).cross(chord)) / length
        }.max() ?? 0
    }

    private static func snapToExisting(
        _ index: Int,
        splits: [StructuralSplit],
        count: Int
    ) -> Int {
        var best: (distance: Int, index: Int)?
        for split in splits {
            let forward = positiveModulo(index + count - split.index, count)
            let candidate = (min(forward, count - forward), split.index)
            if candidate.0 <= PlanningConstants.splitSnapSamples,
               best == nil || candidate.0 < best!.distance
            {
                best = candidate
            }
        }
        return best?.index ?? index
    }

    private static func deduplicatedSplits(_ splits: [StructuralSplit]) -> [StructuralSplit] {
        var result: [StructuralSplit] = []
        for split in splits where result.last?.index != split.index { result.append(split) }
        return result
    }

    private static func findExtrema(
        smoothed: [Point2D],
        start: Int,
        length: Int
    ) -> [StructuralSplit] {
        guard length >= 2 * PlanningConstants.splitSnapSamples + 2 else { return [] }
        let bounds = Bounds(points: smoothed)!
        let diagonal = hypot(bounds.width, bounds.height)
        let prominence = max(
            diagonal * PlanningConstants.extremumProminenceFraction,
            PlanningConstants.extremumProminence
        )
        var result: [StructuralSplit] = []
        for axis in 0..<2 {
            func coordinate(_ offset: Int) -> Double {
                let point = smoothed[(start + offset) % smoothed.count]
                return axis == 0 ? point.x : point.y
            }
            var previousSign = 0.0
            var previousEnd = 0
            for offset in 1..<length {
                let delta = coordinate(offset) - coordinate(offset - 1)
                // Rust `f64::signum()` returns +1 for +0 and -1 for -0.
                // Keep that signed-zero behavior because it determines how
                // flat extrema are localized by the pinned planner.
                let sign = delta.sign == .minus ? -1.0 : 1.0
                if sign == 0 { continue }
                if previousSign != 0, sign != previousSign {
                    let candidate = (previousEnd + offset - 1) / 2
                    if candidate >= PlanningConstants.extremumStandoff,
                       candidate + PlanningConstants.extremumStandoff < length
                    {
                        let value = coordinate(candidate)
                        let isMaximum = previousSign > 0
                        func sideIsValid(_ offsets: [Int]) -> Bool {
                            for other in offsets {
                                let raw = value - coordinate(other)
                                let drop = isMaximum ? raw : -raw
                                if drop < -0.05 { return false }
                                if drop >= prominence { return true }
                            }
                            return true
                        }
                        if sideIsValid(Array(0..<candidate).reversed()),
                           sideIsValid(Array((candidate + 1)..<length))
                        {
                            let low = max(candidate - PlanningConstants.extremumRefineWindow, 0)
                            let high = min(candidate + PlanningConstants.extremumRefineWindow, length - 1)
                            let lowClear = max(low, PlanningConstants.extremumStandoff + 1)
                            let highClear = min(
                                high,
                                max(length - (PlanningConstants.extremumStandoff + 2), 0)
                            )
                            let refined: Int
                            if let vertex = parabolaVertex(coordinate, low: low, high: high) {
                                let rounded = Int(vertex.rounded())
                                let clamped = min(max(rounded, lowClear), max(highClear, lowClear))
                                refined = clamped >= low && clamped <= high ? clamped : candidate
                            } else {
                                refined = candidate
                            }
                            result.append(StructuralSplit(
                                index: (start + refined) % smoothed.count,
                                kind: axis == 0 ? .extremumX : .extremumY
                            ))
                        }
                    }
                }
                previousSign = sign
                previousEnd = offset
            }
        }
        return result
    }

    private static func findInflections(
        turns: [Double],
        smoothed: [Point2D],
        start: Int,
        length: Int
    ) -> [StructuralSplit] {
        guard length >= 2 * PlanningConstants.inflectionReach else { return [] }
        let sigma = PlanningConstants.curvatureSigma
        let radius = Int(ceil(sigma * 3))
        let kappa = (0..<length).map { offset -> Double in
            var sum = 0.0
            var weightSum = 0.0
            for delta in -radius...radius {
                let weight = exp(-pow(Double(delta), 2) / (2 * sigma * sigma))
                let index = positiveModulo(start + offset + delta, turns.count)
                sum += weight * turns[index]
                weightSum += weight
            }
            return sum / weightSum
        }
        let threshold = PlanningConstants.sampleSpacing / PlanningConstants.inflectionMaximumRadius
        let interiorLow = min(PlanningConstants.inflectionBoundaryMargin, length / 4)
        let interiorHigh = length - min(PlanningConstants.inflectionBoundaryMargin, length / 4)
        var result: [StructuralSplit] = []
        var offset = PlanningConstants.splitSnapSamples
        while offset + 1 + PlanningConstants.splitSnapSamples < length {
            if kappa[offset] * kappa[offset + 1] < 0 {
                let backStart = max(offset - PlanningConstants.inflectionReach, interiorLow)
                let reachesBack = backStart <= offset && kappa[backStart...offset].contains {
                    abs($0) >= threshold && numericSign($0) == numericSign(kappa[offset])
                }
                let forwardEnd = min(offset + 1 + PlanningConstants.inflectionReach, length - 1, interiorHigh)
                let reachesForward = offset < forwardEnd && kappa[(offset + 1)...forwardEnd].contains {
                    abs($0) >= threshold && numericSign($0) == numericSign(kappa[offset + 1])
                }
                let backNet = backStart <= offset ? kappa[backStart...offset].reduce(0, +) : 0
                let forwardNet = offset < forwardEnd ? kappa[(offset + 1)...forwardEnd].reduce(0, +) : 0
                let minimumSide = PlanningConstants.inflectionMinimumSideTurnDegrees * .pi / 180
                let integrated = numericSign(backNet) == numericSign(kappa[offset])
                    && numericSign(forwardNet) == numericSign(kappa[offset + 1])
                    && abs(backNet) >= minimumSide
                    && abs(forwardNet) >= minimumSide
                if reachesBack, reachesForward, integrated {
                    result.append(StructuralSplit(index: (start + offset) % turns.count, kind: .inflection))
                    offset += PlanningConstants.inflectionReach
                    continue
                }
            }
            offset += 1
        }
        return result
    }

    private static func parabolaVertex(
        _ function: (Int) -> Double,
        low: Int,
        high: Int
    ) -> Double? {
        guard high - low + 1 >= 5 else { return nil }
        let midpoint = Double(low + high) / 2
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
        var t0 = 0.0, t1 = 0.0, t2 = 0.0
        for index in low...high {
            let x = Double(index) - midpoint
            let y = function(index)
            let x2 = x * x
            s0 += 1; s1 += x; s2 += x2; s3 += x2 * x; s4 += x2 * x2
            t0 += y; t1 += x * y; t2 += x2 * y
        }
        let determinant = s4 * (s2 * s0 - s1 * s1)
            - s3 * (s3 * s0 - s1 * s2)
            + s2 * (s3 * s1 - s2 * s2)
        guard abs(determinant) >= 1e-12 else { return nil }
        let a = (t2 * (s2 * s0 - s1 * s1) - s3 * (t1 * s0 - s1 * t0)
            + s2 * (t1 * s1 - s2 * t0)) / determinant
        let b = (s4 * (t1 * s0 - t0 * s1) - t2 * (s3 * s0 - s1 * s2)
            + s2 * (s3 * t0 - s2 * t1)) / determinant
        guard abs(a) >= 1e-12 else { return nil }
        return -b / (2 * a) + midpoint
    }
}

@inline(__always)
func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
}
