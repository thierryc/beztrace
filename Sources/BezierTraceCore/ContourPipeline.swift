// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct ContourExtractionResult: Equatable, Sendable {
    let preparedRaster: PreparedRaster
    let contours: [SubpixelContour]
}

struct InternalTraceResult: Equatable, Sendable {
    let preparedRaster: PreparedRaster
    let outline: ValidatedOutline
}

enum ContourPipeline {
    static func extract(
        data: Data,
        options: RasterPreparationOptions = RasterPreparationOptions()
    ) throws -> ContourExtractionResult {
        guard options.targetHeight.isFinite,
              options.targetHeight > 0,
              options.minimumContourArea.isFinite,
              options.minimumContourArea >= 0
        else {
            throw CoreError.invalidOptions
        }
        let prepared = try RasterPreparer.prepare(data: data, options: options)
        return try extract(prepared: prepared, options: options)
    }

    static func extract(
        prepared: PreparedRaster,
        options: RasterPreparationOptions
    ) throws -> ContourExtractionResult {
        let scale = options.targetHeight / Double(prepared.raster.height)
        let minimumAreaPixels = max(options.minimumContourArea / (scale * scale), 2)
        let contours = SubpixelExtractor.glyphContours(
            raster: prepared.raster,
            threshold: prepared.threshold,
            invert: prepared.invert,
            minimumAreaPixels: minimumAreaPixels
        )
        guard !contours.isEmpty else { throw CoreError.noContours }
        guard contours.allSatisfy(\.isFinite) else { throw CoreError.nonFiniteGeometry }
        return ContourExtractionResult(preparedRaster: prepared, contours: contours)
    }

    static func traceValidated(
        data: Data,
        configuration: TraceConfiguration = .capturedDefaults,
        rasterOptions: RasterPreparationOptions = RasterPreparationOptions()
    ) throws -> InternalTraceResult {
        guard configuration.targetHeight.isFinite, configuration.targetHeight > 0,
              configuration.fitAccuracy.isFinite, configuration.fitAccuracy > 0,
              configuration.smoothing.isFinite, configuration.smoothing > 0,
              configuration.cornerThresholdDegrees.isFinite,
              configuration.cornerThresholdDegrees > 0,
              configuration.grid >= 0,
              configuration.structureGrid >= 0,
              configuration.chamferSize.isFinite, configuration.chamferSize >= 0,
              configuration.chamferMinimumEdge.isFinite,
              configuration.chamferMinimumEdge >= 0
        else { throw CoreError.invalidOptions }

        var options = rasterOptions
        options.targetHeight = configuration.targetHeight
        let prepared = try RasterPreparer.prepare(data: data, options: options)
        return try traceValidated(
            prepared: prepared,
            configuration: configuration,
            rasterOptions: options
        )
    }

    static func traceValidated(
        prepared: PreparedRaster,
        configuration: TraceConfiguration,
        rasterOptions: RasterPreparationOptions
    ) throws -> InternalTraceResult {
        var options = rasterOptions
        options.targetHeight = configuration.targetHeight
        let extraction = try extract(prepared: prepared, options: options)
        let prepared = extraction.preparedRaster
        let scale = configuration.targetHeight / Double(prepared.raster.height)
        let accuracy = min(max(configuration.fitAccuracy / scale, 0.5), 3)
        let raster = RasterTarget(
            raster: prepared.raster,
            invert: prepared.invert,
            pixelsPerUnit: 1 / scale
        )

        var fitted: [FittedContour] = []
        fitted.reserveCapacity(extraction.contours.count)
        for contour in extraction.contours {
            switch ContourPlanner.plan(
                contour: contour,
                configuration: configuration,
                raster: configuration.refineRaster ? raster : nil
            ) {
            case .tooSmall:
                let segments = contour.points.indices.map { index in
                    lineCubic(
                        from: contour.points[index],
                        to: contour.points[(index + 1) % contour.points.count]
                    )
                }
                fitted.append(FittedContour(
                    segments: segments,
                    isLine: Array(repeating: true, count: segments.count),
                    jointKinds: Array(repeating: .fitterJoint, count: segments.count)
                ))
            case .noSplits(let smoothed):
                // The pinned implementation returns this closed fallback
                // before raster refinement and fitting-finish passes.
                fitted.append(ContourFitter.fitClosed(smoothed: smoothed, accuracy: accuracy))
            case .plan(let plan):
                var result = ContourFitter.fitInitial(plan: plan, accuracy: accuracy)
                if configuration.refineRaster { result = ContourRefiner.refine(result, raster: raster) }
                result = FittingFinish.harmonize(result)
                result = FittingFinish.capHandleReach(result)
                fitted.append(result)
            }
        }
        let paths = fitted.map { BezierPathContour($0.scaled(by: scale)) }
        let cleaned = CleanupPipeline.process(paths, configuration: configuration)
        return InternalTraceResult(
            preparedRaster: prepared,
            outline: try OutlineValidator.validate(paths: cleaned)
        )
    }
}
