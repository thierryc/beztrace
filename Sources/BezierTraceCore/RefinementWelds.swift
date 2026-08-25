// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementWelds {
    private static let maximumChordUnits = 12.0
    private static let maximumReachUnits = 45.0
    private static let minimumBreakDegrees = 45.0
    private static let inkProbeFraction = 0.35
    private static let minimumInkCoverage = 0.2

    static func weldConvexTips(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        while contour.segments.count >= 3 {
            let count = contour.segments.count
            var welded = false
            for index in 0..<count where contour.isLine[index] {
                let start = contour.segments[index].start
                let end = contour.segments[index].end
                guard start.distance(to: end) <= maximumChordUnits * raster.pixelsPerUnit else { continue }
                let previous = (index + count - 1) % count
                let next = (index + 1) % count
                guard previous != index, next != index else { continue }
                let incoming = contour.isLine[previous]
                    ? contour.segments[previous].end - contour.segments[previous].start
                    : contour.segments[previous].end - contour.segments[previous].control2
                let outgoing = contour.isLine[next]
                    ? contour.segments[next].end - contour.segments[next].start
                    : contour.segments[next].control1 - contour.segments[next].start
                guard let incomingDirection = incoming.normalized(),
                      let outgoingDirection = outgoing.normalized(),
                      let flatDirection = (end - start).normalized()
                else { continue }
                let minimumCosine = cos(minimumBreakDegrees * .pi / 180)
                if incomingDirection.dot(flatDirection) > minimumCosine,
                   flatDirection.dot(outgoingDirection) > minimumCosine
                {
                    continue
                }
                let cross = incomingDirection.cross(outgoingDirection)
                guard inkLeft ? cross > 0 : cross < 0, abs(cross) >= 1e-9 else { continue }
                let parameter = (end - start).cross(outgoingDirection) / cross
                let apex = start + incomingDirection * parameter
                let midpoint = start.interpolated(to: end, t: 0.5)
                guard parameter >= 0,
                      apex.distance(to: midpoint) <= maximumReachUnits * raster.pixelsPerUnit
                else { continue }
                let probe = midpoint.interpolated(to: apex, t: inkProbeFraction)
                guard raster.coverage(x: probe.x, yUp: probe.y) >= minimumInkCoverage else { continue }

                if contour.isLine[previous] {
                    contour.segments[previous] = lineCubic(from: contour.segments[previous].start, to: apex)
                } else {
                    contour.segments[previous].end = apex
                }
                if contour.isLine[next] {
                    contour.segments[next] = lineCubic(from: apex, to: contour.segments[next].end)
                } else {
                    contour.segments[next].start = apex
                }
                contour.segments.remove(at: index)
                contour.isLine.remove(at: index)
                contour.jointKinds.remove(at: index)
                contour.jointKinds[index < next ? index : 0] = .corner
                welded = true
                break
            }
            if !welded { break }
        }
        return contour
    }
}
