// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementVerify {
    private static let coverageDrift = 0.35
    private static let minimumRun = 15
    private static let maximumResidual = 8
    private static let angleSteps = [0.0, -8.0, 8.0, -16.0, 16.0]

    static func verifyCoverage(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        let polylines = ContourRefiner.allPolylines(contour)
        func driftRun(_ segment: CubicBezier, skipStart: Bool, skipEnd: Bool) -> Int {
            let points = ContourRefiner.sampleCubic(segment)
            let zone = points.count * 3 / 20
            let low = skipStart ? zone : 0
            let high = skipEnd ? points.count - min(zone, points.count) : points.count
            var worst = 0
            var run = 0
            for point in points[low..<high] {
                let coverage = raster.coverage(x: point.x, yUp: point.y)
                if abs(coverage - 0.5) >= coverageDrift {
                    run += 1
                    worst = max(worst, run)
                } else {
                    run = 0
                }
            }
            return worst
        }

        for index in 0..<count where !contour.isLine[index] {
            let startFree = contour.jointKinds[index] == .corner
            let endFree = contour.jointKinds[(index + 1) % count] == .corner
            let run = driftRun(contour.segments[index], skipStart: startFree, skipEnd: endFree)
            guard run >= minimumRun else { continue }
            let segment = contour.segments[index]
            let firstHandle = segment.control1 - segment.start
            let secondHandle = segment.control2 - segment.end
            guard let firstDirection = firstHandle.normalized(),
                  let secondDirection = secondHandle.normalized(),
                  startFree || endFree
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
            let baseLoss = ContourRefiner.bandLoss(band, candidate: polylines[index], inkLeft: inkLeft)
            var best: (segment: CubicBezier, loss: Double, run: Int)?
            for startAngle in angleSteps {
                if startAngle != 0, !startFree { continue }
                for endAngle in angleSteps {
                    if endAngle != 0, !endFree { continue }
                    let candidate = ContourRefiner.optimizeHandles(
                        start: segment.start,
                        startDirection: rotated(firstDirection, degrees: startAngle),
                        endDirection: rotated(secondDirection, degrees: endAngle),
                        end: segment.end,
                        initial: (firstHandle.magnitude, secondHandle.magnitude),
                        band: band,
                        inkLeft: inkLeft
                    )
                    let candidateRun = driftRun(
                        candidate.segment,
                        skipStart: startFree,
                        skipEnd: endFree
                    )
                    if best == nil || candidateRun < best!.run {
                        best = (candidate.segment, candidate.loss, candidateRun)
                    }
                }
            }
            if let best,
               best.run * 2 <= run,
               best.run <= maximumResidual,
               best.loss <= baseLoss
            {
                contour.segments[index] = best.segment
            }
        }
        return contour
    }

    private static func rotated(_ vector: Vector2D, degrees: Double) -> Vector2D {
        let angle = degrees * .pi / 180
        let sine = sin(angle)
        let cosine = cos(angle)
        return Vector2D(
            dx: vector.dx * cosine - vector.dy * sine,
            dy: vector.dx * sine + vector.dy * cosine
        )
    }
}
