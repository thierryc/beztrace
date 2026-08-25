// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementLines {
    private static let inflectionReachMaximum = 0.67
    private static let inflectionMinimumTurn = 0.12
    private static let inflectionMinimumBaseLoss = 0.06
    private static let inflectionLossFactor = 1.8
    private static let inflectionLossFloor = 0.005
    private static let extremumAxisSine = 0.26
    private static let extremumMaximumFlankRatio = 3.0
    private static let extremumMaximumUnits = 60.0
    private static let extremumLossFloor = 0.004
    private static let cornerMicroMaximumChord = 18.0
    private static let cornerMicroMaximumFraction = 0.35
    private static let cornerMicroMaximumReach = 24.0
    private static let cornerMicroLossFactor = 1.3
    private static let cornerMicroLossFloor = 0.002

    static func smoothInflectionLines(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        while contour.segments.count >= 3 {
            let count = contour.segments.count
            let polylines = ContourRefiner.allPolylines(contour)
            var changed = false
            for lineIndex in 0..<count {
                let previous = (lineIndex + count - 1) % count
                let next = (lineIndex + 1) % count
                guard contour.isLine[lineIndex],
                      !contour.isLine[previous], !contour.isLine[next],
                      contour.jointKinds[lineIndex] == .tangent,
                      contour.jointKinds[next] == .tangent
                else { continue }
                let previousTurn = ContourRefiner.polylineTurn(polylines[previous])
                let nextTurn = ContourRefiner.polylineTurn(polylines[next])
                let start = contour.segments[previous].start
                let end = contour.segments[next].end
                let lineStart = contour.segments[lineIndex].start
                let lineEnd = contour.segments[lineIndex].end
                let lineVector = lineEnd - lineStart
                let startHandle = contour.segments[previous].control1 - start
                let endHandle = contour.segments[next].control2 - end
                guard let lineDirection = lineVector.normalized(),
                      let startDirection = startHandle.normalized(),
                      let endDirection = endHandle.normalized()
                else { continue }

                let opposite = previousTurn * nextTurn < 0
                    && abs(previousTurn) >= inflectionMinimumTurn
                    && abs(nextTurn) >= inflectionMinimumTurn
                let flank = min(arcLength(polylines[previous]), arcLength(polylines[next]))
                guard lineVector.magnitude <= flank * extremumMaximumFlankRatio else { continue }
                let extremum: SplitKind?
                if opposite {
                    extremum = nil
                } else if max(abs(previousTurn), abs(nextTurn)) >= inflectionMinimumTurn {
                    guard lineVector.magnitude <= extremumMaximumUnits * raster.pixelsPerUnit else {
                        continue
                    }
                    if abs(lineDirection.dx) < extremumAxisSine {
                        extremum = .extremumX
                    } else if abs(lineDirection.dy) < extremumAxisSine {
                        extremum = .extremumY
                    } else {
                        continue
                    }
                } else {
                    continue
                }

                let region = polylines[previous]
                    + Array(polylines[lineIndex].dropFirst())
                    + Array(polylines[next].dropFirst())
                let fixed = [
                    polylines[(previous + count - 1) % count],
                    polylines[(next + 1) % count],
                ]
                let band = ContourRefiner.collectBand(raster: raster, region: region, fixed: fixed)
                guard band.count >= 16 else { continue }
                let baseLoss = ContourRefiner.bandLoss(band, candidate: region, inkLeft: inkLeft)
                guard extremum != nil || baseLoss >= inflectionMinimumBaseLoss else { continue }

                var best: (loss: Double, first: CubicBezier, second: CubicBezier)?
                for fraction in [0.35, 0.5, 0.65] {
                    let joint = lineStart.interpolated(to: lineEnd, t: fraction)
                    let firstChord = start.distance(to: joint)
                    let secondChord = joint.distance(to: end)
                    let first = ContourRefiner.optimizeHandles(
                        start: start,
                        startDirection: startDirection,
                        endDirection: -lineDirection,
                        end: joint,
                        initial: (firstChord / 3, firstChord / 3),
                        band: band,
                        inkLeft: inkLeft
                    )
                    let firstPolyline = ContourRefiner.sampleCubic(first.segment)
                    let second = ContourRefiner.optimizeHandles(
                        start: joint,
                        startDirection: lineDirection,
                        endDirection: endDirection,
                        end: end,
                        initial: (secondChord / 3, secondChord / 3),
                        band: band,
                        inkLeft: inkLeft,
                        prefix: firstPolyline
                    )
                    if best == nil || second.loss < best!.loss {
                        best = (second.loss, first.segment, second.segment)
                    }
                }
                guard let best else { continue }
                let accept = extremum == nil
                    ? best.loss <= inflectionLossFactor * baseLoss + inflectionLossFloor
                    : best.loss <= baseLoss + extremumLossFloor
                guard accept else { continue }

                contour.segments[previous] = capReach(best.first, maximumFraction: inflectionReachMaximum)
                contour.isLine[previous] = false
                contour.segments[lineIndex] = capReach(best.second, maximumFraction: inflectionReachMaximum)
                contour.isLine[lineIndex] = false
                contour.jointKinds[lineIndex] = extremum ?? .inflection
                contour.segments.remove(at: next)
                contour.isLine.remove(at: next)
                contour.jointKinds.remove(at: next)
                changed = true
                break
            }
            if !changed { break }
        }
        return contour
    }

    static func collapseCornerMicroLines(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        while contour.segments.count >= 4 {
            let count = contour.segments.count
            var collapsed = false
            for index in 0..<count {
                let previous = (index + count - 1) % count
                let next = (index + 1) % count
                guard contour.isLine[index], contour.isLine[previous] || contour.isLine[next] else {
                    continue
                }
                let micro = contour.segments[index]
                let chord = micro.start.distance(to: micro.end)
                guard chord <= cornerMicroMaximumChord else { continue }
                let previousLength = contour.segments[previous].start.distance(to: contour.segments[previous].end)
                let nextLength = contour.segments[next].start.distance(to: contour.segments[next].end)
                guard previousLength >= 1e-6, nextLength >= 1e-6,
                      chord <= cornerMicroMaximumFraction * min(previousLength, nextLength),
                      let targets = collapseTargets(contour, previous: previous, micro: index, next: next)
                else { continue }

                let original = polyline(contour, index: previous)
                    + Array(polyline(contour, index: index).dropFirst())
                    + Array(polyline(contour, index: next).dropFirst())
                let candidate = segmentPolyline(targets.0, isLine: contour.isLine[previous])
                    + Array(segmentPolyline(targets.1, isLine: contour.isLine[next]).dropFirst())
                let band = ContourRefiner.collectBand(
                    raster: raster,
                    region: original,
                    fixed: [
                        polyline(contour, index: (previous + count - 1) % count),
                        polyline(contour, index: (next + 1) % count),
                    ]
                )
                guard band.count >= 12 else { continue }
                let originalLoss = ContourRefiner.bandLoss(band, candidate: original, inkLeft: inkLeft)
                let candidateLoss = ContourRefiner.bandLoss(band, candidate: candidate, inkLeft: inkLeft)
                guard candidateLoss <= cornerMicroLossFactor * originalLoss + cornerMicroLossFloor else {
                    continue
                }
                contour.segments[previous] = targets.0
                contour.segments[next] = targets.1
                contour.jointKinds[next] = .corner
                contour.segments.remove(at: index)
                contour.isLine.remove(at: index)
                contour.jointKinds.remove(at: index)
                collapsed = true
                break
            }
            if !collapsed { break }
        }
        return contour
    }

    private static func collapseTargets(
        _ contour: FittedContour,
        previous: Int,
        micro: Int,
        next: Int
    ) -> (CubicBezier, CubicBezier)? {
        let stub = contour.segments[micro]
        let previousIsLine = contour.isLine[previous]
        let nextIsLine = contour.isLine[next]
        if previousIsLine, nextIsLine {
            let start = contour.segments[previous].start
            let end = contour.segments[next].end
            guard let corner = ContourRefiner.rayIntersection(
                start: start,
                direction: stub.start - start,
                otherStart: end,
                otherDirection: stub.end - end
            ), corner.distance(to: stub.start.interpolated(to: stub.end, t: 0.5))
                <= cornerMicroMaximumReach
            else { return nil }
            return (
                CubicBezier(start: start, control1: start, control2: corner, end: corner),
                CubicBezier(start: corner, control1: corner, control2: end, end: end)
            )
        }
        if nextIsLine {
            let joint = stub.end
            let delta = joint - stub.start
            var rebuilt = contour.segments[previous]
            rebuilt.control2 = rebuilt.control2 + delta
            rebuilt.end = joint
            return (rebuilt, contour.segments[next])
        }
        let joint = stub.start
        let delta = joint - stub.end
        var rebuilt = contour.segments[next]
        rebuilt.control1 = rebuilt.control1 + delta
        rebuilt.start = joint
        return (contour.segments[previous], rebuilt)
    }

    private static func segmentPolyline(_ segment: CubicBezier, isLine: Bool) -> [Point2D] {
        isLine ? [segment.start, segment.end] : ContourRefiner.sampleCubic(segment)
    }

    private static func polyline(_ contour: FittedContour, index: Int) -> [Point2D] {
        segmentPolyline(contour.segments[index], isLine: contour.isLine[index])
    }

    private static func arcLength(_ polyline: [Point2D]) -> Double {
        guard polyline.count >= 2 else { return 0 }
        return zip(polyline, polyline.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    private static func capReach(_ segment: CubicBezier, maximumFraction: Double) -> CubicBezier {
        let chordVector = segment.end - segment.start
        let chord = chordVector.magnitude
        guard chord >= 1e-9 else { return segment }
        let direction = chordVector / chord
        let firstHandle = segment.control1 - segment.start
        let secondHandle = segment.control2 - segment.end
        let reach = firstHandle.dot(direction) - secondHandle.dot(direction)
        let limit = chord * maximumFraction
        guard reach > limit else { return segment }
        let scale = limit / reach
        return CubicBezier(
            start: segment.start,
            control1: segment.start + firstHandle * scale,
            control2: segment.end + secondHandle * scale,
            end: segment.end
        )
    }
}
