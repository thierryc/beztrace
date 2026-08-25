// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct RefinementBandPoint: Sendable {
    let point: Point2D
    let sourceCoverage: Double
    let fixedSignedDistance: Double
}

enum ContourRefiner {
    private static let bandRadius = 2.0
    private static let minimumHandleFraction = 0.02
    private static let maximumHandleFraction = 1.1
    private static let goldenIterations = 16
    private static let descentSweeps = 2
    private static let balanceSlackRelative = 2.0
    private static let balanceSlackFloor = 0.004
    private static let balanceSlackCeiling = 0.09
    private static let balanceMinimumSpread = 1.0
    private static let handleReachMaximum = 0.9

    static func refine(_ input: FittedContour, raster: RasterTarget) -> FittedContour {
        guard input.segments.count >= 2, let inkLeft = inkIsLeft(raster, contour: input) else {
            return input
        }
        var contour = input
        contour = RefinementFlats.junctionFlats(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementLines.smoothInflectionLines(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementLines.collapseCornerMicroLines(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementWelds.weldConvexTips(contour, raster: raster, inkLeft: inkLeft)
        let touched = contour.segments.indices.compactMap {
            contour.jointKinds[$0] == .corner ? contour.segments[$0].start : nil
        }
        contour = RefinementMerge.merge(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementPolish.polish(contour, raster: raster, inkLeft: inkLeft, touched: touched)
        contour = RefinementPolish.rebalance(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementPolish.slide(contour, raster: raster, inkLeft: inkLeft)
        contour = RefinementVerify.verifyCoverage(contour, raster: raster, inkLeft: inkLeft)
        return contour
    }

    static func inkIsLeft(_ raster: RasterTarget, contour: FittedContour) -> Bool? {
        var left = 0.0
        var right = 0.0
        for segment in contour.segments {
            for sample in 1..<4 {
                let parameter = Double(sample) * 0.25
                let point = segment.point(at: parameter)
                let derivative = segment.derivative(at: parameter)
                guard derivative.magnitude >= 1e-9 else { continue }
                let normal = Vector2D(dx: -derivative.dy, dy: derivative.dx) / derivative.magnitude
                for offset in [0.75, 1.5] {
                    left += raster.coverage(
                        x: point.x + normal.dx * offset,
                        yUp: point.y + normal.dy * offset
                    )
                    right += raster.coverage(
                        x: point.x - normal.dx * offset,
                        yUp: point.y - normal.dy * offset
                    )
                }
            }
        }
        guard abs(left - right) >= 1e-6 else { return nil }
        return left > right
    }

    static func allPolylines(_ contour: FittedContour) -> [[Point2D]] {
        contour.segments.indices.map { index in
            contour.isLine[index]
                ? [contour.segments[index].start, contour.segments[index].end]
                : sampleCubic(contour.segments[index])
        }
    }

    static func sampleCubic(_ segment: CubicBezier) -> [Point2D] {
        let chord = segment.start.distance(to: segment.end)
        let count = min(max(Int(chord / 3), 8), 64)
        return (0...count).map { segment.point(at: Double($0) / Double(count)) }
    }

    static func polylineTurn(_ polyline: [Point2D]) -> Double {
        guard polyline.count >= 3 else { return 0 }
        return (0..<(polyline.count - 2)).reduce(0) { sum, index in
            let first = polyline[index + 1] - polyline[index]
            let second = polyline[index + 2] - polyline[index + 1]
            return sum + atan2(first.cross(second), first.dot(second))
        }
    }

    static func signedDistance(_ point: Point2D, to polyline: [Point2D]) -> Double {
        var bestSquaredDistance = Double.infinity
        var bestSign = 1.0
        guard polyline.count >= 2 else { return bestSquaredDistance }
        for index in 0..<(polyline.count - 1) {
            let start = polyline[index]
            let direction = polyline[index + 1] - start
            let lengthSquared = direction.dot(direction)
            guard lengthSquared >= 1e-18 else { continue }
            let parameter = min(max((point - start).dot(direction) / lengthSquared, 0), 1)
            let projection = start + direction * parameter
            let difference = point - projection
            let squaredDistance = difference.dot(difference)
            guard squaredDistance < bestSquaredDistance else { continue }
            bestSquaredDistance = squaredDistance
            if parameter <= 1e-9 || parameter >= 1 - 1e-9 {
                let vertex = parameter <= 1e-9 ? index : index + 1
                var pseudoNormal = Vector2D.zero
                var backward = vertex
                while backward > 0 {
                    backward -= 1
                    let candidate = polyline[vertex] - polyline[backward]
                    if candidate.magnitude > 1e-9 {
                        let unit = candidate.normalized()!
                        pseudoNormal = pseudoNormal + Vector2D(dx: -unit.dy, dy: unit.dx)
                        break
                    }
                }
                var forward = vertex
                while forward + 1 < polyline.count {
                    forward += 1
                    let candidate = polyline[forward] - polyline[vertex]
                    if candidate.magnitude > 1e-9 {
                        let unit = candidate.normalized()!
                        pseudoNormal = pseudoNormal + Vector2D(dx: -unit.dy, dy: unit.dx)
                        break
                    }
                }
                bestSign = (point - polyline[vertex]).dot(pseudoNormal) >= 0 ? 1 : -1
            } else {
                bestSign = direction.cross(point - start) >= 0 ? 1 : -1
            }
        }
        return bestSign * sqrt(bestSquaredDistance)
    }

    static func collectBand(
        raster: RasterTarget,
        region: [Point2D],
        fixed: [[Point2D]]
    ) -> [RefinementBandPoint] {
        guard let bounds = Bounds(points: region) else { return [] }
        let minimumX = max(Int(floor(bounds.minX - bandRadius)), 0)
        let minimumY = max(Int(floor(bounds.minY - bandRadius)), 0)
        let maximumX = min(Int(ceil(bounds.maxX + bandRadius)), raster.width - 1)
        let maximumY = min(Int(ceil(bounds.maxY + bandRadius)), raster.height - 1)
        guard maximumX >= minimumX, maximumY >= minimumY else { return [] }
        let bandWidth = maximumX - minimumX + 1
        let bandHeight = maximumY - minimumY + 1
        let stampRadius = Int(ceil(bandRadius)) + 2
        var mask = Array(repeating: false, count: bandWidth * bandHeight)
        for point in region {
            let centerX = Int(floor(point.x))
            let centerY = Int(floor(point.y))
            for y in max(centerY - stampRadius, minimumY)...min(centerY + stampRadius, maximumY) {
                for x in max(centerX - stampRadius, minimumX)...min(centerX + stampRadius, maximumX) {
                    mask[(y - minimumY) * bandWidth + x - minimumX] = true
                }
            }
        }

        var band: [RefinementBandPoint] = []
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                guard mask[(y - minimumY) * bandWidth + x - minimumX] else { continue }
                let point = Point2D(x: Double(x) + 0.5, y: Double(y) + 0.5)
                let distance = signedDistance(point, to: region)
                guard abs(distance) <= bandRadius else { continue }
                var fixedDistance = Double.infinity
                for polyline in fixed {
                    let candidate = signedDistance(point, to: polyline)
                    if abs(candidate) < abs(fixedDistance) { fixedDistance = candidate }
                }
                band.append(RefinementBandPoint(
                    point: point,
                    sourceCoverage: raster.coverage(x: point.x, yUp: point.y),
                    fixedSignedDistance: fixedDistance
                ))
            }
        }
        return band
    }

    static func bandLoss(
        _ band: [RefinementBandPoint],
        candidate: [Point2D],
        inkLeft: Bool
    ) -> Double {
        guard !band.isEmpty else { return 0 }
        let sum = band.reduce(0) { result, sample in
            let candidateDistance = signedDistance(sample.point, to: candidate)
            let distance = abs(sample.fixedSignedDistance) < abs(candidateDistance)
                ? sample.fixedSignedDistance
                : candidateDistance
            let towardInk = inkLeft ? distance : -distance
            let predicted = min(max(0.5 + towardInk, 0), 1)
            let error = predicted - sample.sourceCoverage
            return result + error * error
        }
        return sum / Double(band.count)
    }

    static func optimizeHandles(
        start: Point2D,
        startDirection: Vector2D,
        endDirection: Vector2D,
        end: Point2D,
        initial: (Double, Double),
        band: [RefinementBandPoint],
        inkLeft: Bool,
        prefix: [Point2D] = [],
        suffix: [Point2D] = []
    ) -> (segment: CubicBezier, loss: Double) {
        let chord = start.distance(to: end)
        let low = chord * minimumHandleFraction
        let high = chord * maximumHandleFraction
        let triangle = handleTriangle(
            start: start,
            startDirection: startDirection,
            end: end,
            endDirection: endDirection
        )
        let highStart = max(min(high, triangle?.0 ?? high), low)
        let highEnd = max(min(high, triangle?.1 ?? high), low)

        func evaluate(_ alpha: Double, _ beta: Double) -> Double {
            let segment = CubicBezier(
                start: start,
                control1: start + startDirection * alpha,
                control2: end + endDirection * beta,
                end: end
            )
            let points = sampleCubic(segment)
            if prefix.isEmpty, suffix.isEmpty {
                return bandLoss(band, candidate: points, inkLeft: inkLeft)
            }
            return bandLoss(band, candidate: prefix + points + suffix, inkLeft: inkLeft)
        }

        var alpha = min(max(initial.0, low), highStart)
        var beta = min(max(initial.1, low), highEnd)
        for _ in 0..<descentSweeps {
            let difference = (alpha - beta) * 0.5
            let mean = goldenMinimum(low: low, high: high) { mean in
                evaluate(
                    min(max(mean + difference, low), highStart),
                    min(max(mean - difference, low), highEnd)
                )
            }
            alpha = min(max(mean + difference, low), highStart)
            beta = min(max(mean - difference, low), highEnd)
            let currentMean = (alpha + beta) * 0.5
            let span = high - low
            let optimizedDifference = goldenMinimum(low: -span, high: span) { difference in
                evaluate(
                    min(max(currentMean + difference, low), highStart),
                    min(max(currentMean - difference, low), highEnd)
                )
            }
            beta = min(max(currentMean - optimizedDifference, low), highEnd)
            alpha = goldenMinimum(low: low, high: highStart) { evaluate($0, beta) }
            beta = goldenMinimum(low: low, high: highEnd) { evaluate(alpha, $0) }
        }

        let optimumLoss = evaluate(alpha, beta)
        let spans = handleSpans(
            start: start,
            startDirection: startDirection,
            end: end,
            endDirection: endDirection
        )
        let maximumSpan = max(spans?.0 ?? 1, spans?.1 ?? 1)
        let firstWeight = (spans?.0 ?? 1) / maximumSpan
        let secondWeight = (spans?.1 ?? 1) / maximumSpan
        if abs(alpha / firstWeight - beta / secondWeight) > balanceMinimumSpread {
            let target = min(optimumLoss * balanceSlackRelative + balanceSlackFloor, balanceSlackCeiling)
            func ray(_ value: Double) -> (Double, Double) {
                (
                    min(max(value * firstWeight, low), highStart),
                    min(max(value * secondWeight, low), highEnd)
                )
            }
            let value = goldenMinimum(
                low: low,
                high: min(highStart / firstWeight, highEnd / secondWeight)
            ) {
                let point = ray($0)
                return evaluate(point.0, point.1)
            }
            let balanced = ray(value)
            if evaluate(balanced.0, balanced.1) <= target {
                alpha = balanced.0
                beta = balanced.1
            }
        }

        if chord > 1e-9 {
            let chordDirection = (end - start) / chord
            let reach = alpha * startDirection.dot(chordDirection)
                - beta * endDirection.dot(chordDirection)
            let limit = chord * handleReachMaximum
            if reach > limit {
                let factor = limit / reach
                alpha *= factor
                beta *= factor
            }
        }
        return (
            CubicBezier(
                start: start,
                control1: start + startDirection * alpha,
                control2: end + endDirection * beta,
                end: end
            ),
            optimumLoss
        )
    }

    static func goldenMinimum(
        low initialLow: Double,
        high initialHigh: Double,
        function: (Double) -> Double
    ) -> Double {
        let inversePhi = 0.618_033_988_749_894_8
        var low = initialLow
        var high = initialHigh
        var first = high - (high - low) * inversePhi
        var second = low + (high - low) * inversePhi
        var firstValue = function(first)
        var secondValue = function(second)
        for _ in 0..<goldenIterations {
            if firstValue <= secondValue {
                high = second
                second = first
                secondValue = firstValue
                first = high - (high - low) * inversePhi
                firstValue = function(first)
            } else {
                low = first
                first = second
                firstValue = secondValue
                second = low + (high - low) * inversePhi
                secondValue = function(second)
            }
        }
        return firstValue <= secondValue ? first : second
    }

    static func handleTriangle(
        start: Point2D,
        startDirection: Vector2D,
        end: Point2D,
        endDirection: Vector2D
    ) -> (Double, Double)? {
        let denominator = startDirection.cross(endDirection)
        guard abs(denominator) >= 1e-9 else { return nil }
        let chord = end - start
        let first = chord.cross(endDirection) / denominator
        let second = chord.cross(startDirection) / denominator
        guard first > 0, second > 0 else { return nil }
        return (first, second)
    }

    static func handleSpans(
        start: Point2D,
        startDirection: Vector2D,
        end: Point2D,
        endDirection: Vector2D
    ) -> (Double, Double)? {
        let chord = end - start
        let length = chord.magnitude
        guard length >= 1e-9 else { return nil }
        let first = abs(chord.dot(startDirection))
        let second = abs(chord.dot(endDirection))
        guard first > length * 0.15, second > length * 0.15 else { return nil }
        return (first, second)
    }

    static func rayIntersection(
        start: Point2D,
        direction: Vector2D,
        otherStart: Point2D,
        otherDirection: Vector2D
    ) -> Point2D? {
        let determinant = direction.dx * -otherDirection.dy - direction.dy * -otherDirection.dx
        guard abs(determinant) >= 1e-9 else { return nil }
        let difference = otherStart - start
        let first = (difference.dx * -otherDirection.dy - difference.dy * -otherDirection.dx)
            / determinant
        let second = (direction.dx * difference.dy - direction.dy * difference.dx) / determinant
        guard first > 0, second > 0 else { return nil }
        return start + direction * first
    }
}
