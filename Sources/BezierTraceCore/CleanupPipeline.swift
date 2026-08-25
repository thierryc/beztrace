// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

enum CleanupPipeline {
    private static let horizontalVerticalThresholdDegrees = 15.0

    static func process(
        _ paths: [BezierPathContour],
        configuration: TraceConfiguration
    ) -> [BezierPathContour] {
        var result = configuration.fixDirection ? CleanupDirection.fixDirections(paths) : paths
        result = result.map(CleanupStraighten.flattenStraightRuns)
        result = result.map(CleanupSimplify.removeRedundantPoints)
        if configuration.grid > 0 {
            result = result.map {
                CleanupSnap.toGrid(
                    $0,
                    fine: Double(configuration.grid),
                    structure: Double(configuration.structureGrid)
                )
            }
        }
        result = result.map { path in
            CleanupSnap.horizontalVerticalHandles(
                path,
                thresholdDegrees: horizontalVerticalThresholdDegrees,
                skip: CleanupSnap.smoothInflectionPoints(path),
                corners: CleanupSnap.cornerAnchorPoints(path)
            )
        }
        result = result.map {
            CleanupInflection.splitInflections($0, grid: Double(max(configuration.grid, 0)))
        }
        if configuration.chamferSize > 0 {
            result = result.map {
                CleanupChamfer.chamfer(
                    $0,
                    size: configuration.chamferSize,
                    minimumEdge: configuration.chamferMinimumEdge
                )
            }
        }
        result = result.map(CleanupEven.evenHandles)
        result = result.map(CleanupEven.capHandles)
        if configuration.grid > 0 { result = result.map(CleanupSnap.roundHandles) }
        return result
    }
}
