// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementMerge {
    private static let absoluteAcceptance = 0.04
    private static let lossFactor = 1.3
    private static let lossFloor = 0.001
    private static let maximumTurn = 1.75
    private static let minimumTurnSign = 0.05
    private static let minimumCornerCosine = 0.866

    static func merge(_ input: FittedContour, raster: RasterTarget, inkLeft: Bool) -> FittedContour {
        var contour = input
        while contour.segments.count >= 3 {
            let count = contour.segments.count
            let polylines = ContourRefiner.allPolylines(contour)
            var didMerge = false
            for index in 0..<count {
                let previous = (index + count - 1) % count
                guard !contour.isLine[previous], !contour.isLine[index] else { continue }
                let mergeable: Bool
                switch contour.jointKinds[index] {
                case .inflection, .fitterJoint:
                    mergeable = true
                case .corner:
                    mergeable = jointBreakCosine(contour, index: index) >= minimumCornerCosine
                default:
                    mergeable = false
                }
                guard mergeable else { continue }
                let previousTurn = ContourRefiner.polylineTurn(polylines[previous])
                let currentTurn = ContourRefiner.polylineTurn(polylines[index])
                if previousTurn * currentTurn < 0,
                   abs(previousTurn) > minimumTurnSign,
                   abs(currentTurn) > minimumTurnSign
                {
                    continue
                }
                guard abs(previousTurn + currentTurn) <= maximumTurn else { continue }

                let start = contour.segments[previous].start
                let end = contour.segments[index].end
                let startHandle = contour.segments[previous].control1 - start
                let endHandle = contour.segments[index].control2 - end
                guard let startDirection = startHandle.normalized(),
                      let endDirection = endHandle.normalized()
                else { continue }
                let region = polylines[previous] + polylines[index].dropFirst()
                let fixed = [polylines[(previous + count - 1) % count], polylines[(index + 1) % count]]
                let band = ContourRefiner.collectBand(raster: raster, region: region, fixed: fixed)
                guard band.count >= 16 else { continue }
                var pairLoss = ContourRefiner.bandLoss(band, candidate: region, inkLeft: inkLeft)
                let initialHandle = start.distance(to: end) / 3
                let merged = ContourRefiner.optimizeHandles(
                    start: start,
                    startDirection: startDirection,
                    endDirection: endDirection,
                    end: end,
                    initial: (initialHandle, initialHandle),
                    band: band,
                    inkLeft: inkLeft
                )

                let joint = contour.segments[index].start
                let previousJointHandle = contour.segments[previous].control2 - joint
                let currentJointHandle = contour.segments[index].control1 - joint
                if let previousJointDirection = previousJointHandle.normalized(),
                   let currentJointDirection = currentJointHandle.normalized()
                {
                    let optimizedPrevious = ContourRefiner.optimizeHandles(
                        start: start,
                        startDirection: startDirection,
                        endDirection: previousJointDirection,
                        end: joint,
                        initial: (startHandle.magnitude, previousJointHandle.magnitude),
                        band: band,
                        inkLeft: inkLeft,
                        suffix: polylines[index]
                    )
                    let optimizedPreviousPolyline = ContourRefiner.sampleCubic(optimizedPrevious.segment)
                    let optimizedCurrent = ContourRefiner.optimizeHandles(
                        start: joint,
                        startDirection: currentJointDirection,
                        endDirection: endDirection,
                        end: end,
                        initial: (currentJointHandle.magnitude, endHandle.magnitude),
                        band: band,
                        inkLeft: inkLeft,
                        prefix: optimizedPreviousPolyline
                    )
                    pairLoss = min(pairLoss, optimizedCurrent.loss)
                }
                let accept = merged.loss <= absoluteAcceptance
                    || merged.loss <= lossFactor * pairLoss + lossFloor
                if accept {
                    contour.segments[previous] = merged.segment
                    contour.segments.remove(at: index)
                    contour.isLine.remove(at: index)
                    contour.jointKinds.remove(at: index)
                    didMerge = true
                    break
                }
            }
            if !didMerge { break }
        }
        return contour
    }

    private static func jointBreakCosine(_ contour: FittedContour, index: Int) -> Double {
        let previous = (index + contour.segments.count - 1) % contour.segments.count
        let incoming = contour.segments[previous].end - contour.segments[previous].control2
        let outgoing = contour.segments[index].control1 - contour.segments[index].start
        guard let first = incoming.normalized(), let second = outgoing.normalized() else { return -1 }
        return first.dot(second)
    }
}
