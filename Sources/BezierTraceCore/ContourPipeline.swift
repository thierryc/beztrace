// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct ContourExtractionResult: Equatable, Sendable {
    let preparedRaster: PreparedRaster
    let contours: [SubpixelContour]
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
}
