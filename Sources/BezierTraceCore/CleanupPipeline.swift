// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

struct CleanupResult: Equatable, Sendable {
    let paths: [BezierPathContour]
    let outline: ValidatedOutline
    let skippedGridContours: Int
}

enum CleanupPipeline {
    private static let horizontalVerticalThresholdDegrees = 15.0

    static func process(
        _ paths: [BezierPathContour],
        configuration: TraceConfiguration,
        curvatureProtected: Set<Int> = []
    ) throws -> CleanupResult {
        var result = configuration.fixDirection ? CleanupDirection.fixDirections(paths) : paths
        result = result.enumerated().map { index, path in
            curvatureProtected.contains(index) ? path : CleanupStraighten.flattenStraightRuns(path)
        }
        result = result.map(CleanupSimplify.removeRedundantPoints)
        result = result.map(CleanupMinimumNodes.ensureThreeOnCurves)

        guard configuration.grid > 0 else {
            let cleaned = result.map { finish($0, configuration: configuration, grid: 0) }
            return CleanupResult(
                paths: cleaned,
                outline: try OutlineValidator.validate(paths: cleaned),
                skippedGridContours: 0
            )
        }

        let candidates = result.map { path in
            finish(
                CleanupSnap.toGrid(
                    path,
                    fine: Double(configuration.grid),
                    structure: Double(configuration.structureGrid)
                ),
                configuration: configuration,
                grid: configuration.grid
            )
        }
        if let outline = try? OutlineValidator.validate(paths: candidates) {
            return CleanupResult(paths: candidates, outline: outline, skippedGridContours: 0)
        }
        let fallback = result.map { finish($0, configuration: configuration, grid: 0) }
        return try selectValidatedGridCandidates(fallback: fallback, candidates: candidates)
    }

    static func selectValidatedGridCandidates(
        fallback: [BezierPathContour],
        candidates: [BezierPathContour]
    ) throws -> CleanupResult {
        precondition(fallback.count == candidates.count)
        let fallbackOutline = try OutlineValidator.validate(paths: fallback)
        if let outline = try? OutlineValidator.validate(paths: candidates) {
            return CleanupResult(paths: candidates, outline: outline, skippedGridContours: 0)
        }

        var accepted = fallback
        var outline = fallbackOutline
        var skipped = 0
        for index in candidates.indices {
            var trial = accepted
            trial[index] = candidates[index]
            if let candidateOutline = try? OutlineValidator.validate(paths: trial) {
                accepted = trial
                outline = candidateOutline
            } else {
                skipped += 1
            }
        }
        return CleanupResult(paths: accepted, outline: outline, skippedGridContours: skipped)
    }

    private static func finish(
        _ path: BezierPathContour,
        configuration: TraceConfiguration,
        grid: Int
    ) -> BezierPathContour {
        var result = CleanupSnap.horizontalVerticalHandles(
            path,
            thresholdDegrees: horizontalVerticalThresholdDegrees,
            skip: CleanupSnap.smoothInflectionPoints(path),
            corners: CleanupSnap.cornerAnchorPoints(path)
        )
        result = CleanupInflection.splitInflections(result, grid: Double(max(grid, 0)))
        if configuration.chamferSize > 0 {
            result = CleanupChamfer.chamfer(
                result,
                size: configuration.chamferSize,
                minimumEdge: configuration.chamferMinimumEdge
            )
        }
        result = CleanupEven.evenHandles(result)
        result = CleanupEven.capHandles(result)
        if grid > 0 { result = CleanupSnap.roundHandles(result) }
        return result
    }
}
