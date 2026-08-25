// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct PlacementPlan {
    let sourceBoundsPixels: Rect
    let inkBoundsPixels: Rect
    let targetHeight: Double
    let scalePerSourcePixel: Double
}

enum PlacementEngine {
    static func validate(_ options: PlacementOptions, sourceSize: (Int, Int)? = nil) throws {
        guard options.targetYMin.isFinite, options.targetYMax.isFinite,
              options.targetYMax > options.targetYMin
        else { throw TraceError.invalidPlacement("targetYMax must be greater than targetYMin") }
        guard options.grid >= 0 else {
            throw TraceError.invalidPlacement("placement grid must be zero or greater")
        }
        switch options.sourceBox {
        case .canvas, .ink:
            break
        case .rectangle(let rect):
            guard rect.isFiniteAndOrdered else {
                throw TraceError.invalidPlacement("source rectangle must be finite with positive size")
            }
            if let sourceSize,
               (rect.minX < 0 || rect.minY < 0
                || rect.maxX > Double(sourceSize.0) || rect.maxY > Double(sourceSize.1))
            {
                throw TraceError.invalidPlacement("source rectangle must lie within the image")
            }
        }
        switch options.horizontalMode {
        case .sidebearings(let left, let right):
            guard left.isFinite, right.isFinite else {
                throw TraceError.invalidPlacement("sidebearings must be finite")
            }
        case .advance(let width, let left):
            guard width.isFinite, width > 0, left.isFinite else {
                throw TraceError.invalidPlacement("advance must be positive and finite; LSB must be finite")
            }
        case .centered(let advance):
            guard advance.isFinite, advance > 0 else {
                throw TraceError.invalidPlacement("centered advance must be positive and finite")
            }
        }
    }

    static func plan(prepared: PreparedRaster, options: PlacementOptions) throws -> PlacementPlan {
        try validate(options, sourceSize: (prepared.sourceWidth, prepared.sourceHeight))
        guard let inkPrepared = inkBounds(
            raster: prepared.raster,
            threshold: prepared.threshold,
            invert: prepared.invert
        ) else { throw TraceError.noContours }
        let sourceScaleX = Double(prepared.sourceWidth) / Double(prepared.raster.width)
        let sourceScaleY = Double(prepared.sourceHeight) / Double(prepared.raster.height)
        let ink = Rect(
            minX: inkPrepared.minX * sourceScaleX,
            minY: inkPrepared.minY * sourceScaleY,
            maxX: inkPrepared.maxX * sourceScaleX,
            maxY: inkPrepared.maxY * sourceScaleY
        )
        let source: Rect
        switch options.sourceBox {
        case .canvas:
            source = Rect(
                minX: 0,
                minY: 0,
                maxX: Double(prepared.sourceWidth),
                maxY: Double(prepared.sourceHeight)
            )
        case .ink:
            source = ink
        case .rectangle(let rect):
            source = rect
        }
        let fraction = source.height / Double(prepared.sourceHeight)
        guard fraction.isFinite, fraction > 0 else { throw TraceError.noContours }
        let targetHeight = (options.targetYMax - options.targetYMin) / fraction
        guard targetHeight.isFinite, targetHeight > 0 else {
            throw TraceError.invalidPlacement("resolved tracing height is invalid")
        }
        return PlacementPlan(
            sourceBoundsPixels: source,
            inkBoundsPixels: ink,
            targetHeight: targetHeight,
            scalePerSourcePixel: targetHeight / Double(prepared.sourceHeight)
        )
    }

    static func position(
        outline: Outline,
        prepared: PreparedRaster,
        options: PlacementOptions,
        plan: PlacementPlan
    ) throws -> (Outline, PlacementReport) {
        guard let bounds = outline.tightBounds else { throw TraceError.noContours }
        let grid = Double(options.grid)
        func snap(_ value: Double) -> Double {
            grid > 0 ? (value / grid).rounded() * grid : value
        }
        let dy = snap(options.targetYMin - bounds.minY)
        let dx: Double
        let advance: Double
        switch options.horizontalMode {
        case .sidebearings(let left, let right):
            dx = snap(left - bounds.minX)
            advance = bounds.maxX + dx + right
        case .advance(let width, let left):
            dx = snap(left - bounds.minX)
            advance = width
        case .centered(let width):
            dx = snap((width - bounds.width) / 2 - bounds.minX)
            advance = width
        }
        let placed = outline.transformed(dx: dx, dy: dy)
        guard let final = placed.tightBounds else { throw TraceError.noContours }
        let left = bounds.minX + dx
        let right = advance - (bounds.maxX + dx)
        let outOfTarget = final.minY < options.targetYMin - 0.5
            || final.maxY > options.targetYMax + 0.5
        return (placed, PlacementReport(
            imageWidth: prepared.sourceWidth,
            imageHeight: prepared.sourceHeight,
            inkBoundsPixels: plan.inkBoundsPixels,
            sourceBoundsPixels: plan.sourceBoundsPixels,
            targetYMin: options.targetYMin,
            targetYMax: options.targetYMax,
            scale: plan.scalePerSourcePixel,
            translationX: dx,
            translationY: dy,
            finalBounds: final,
            advanceWidth: advance,
            leftSideBearing: left,
            rightSideBearing: right,
            outOfTarget: outOfTarget
        ))
    }

    private static func inkBounds(raster: GrayRaster, threshold: UInt8, invert: Bool) -> Rect? {
        let iso = Double(threshold) + 0.5
        var minX = raster.width
        var minY = raster.height
        var maxX = 0
        var maxY = 0
        var found = false
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let value = Double(raster.pixels[y * raster.width + x])
                let isInk = invert ? value > iso : value < iso
                guard isInk else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x + 1)
                maxY = max(maxY, y + 1)
                found = true
            }
        }
        guard found else { return nil }
        return Rect(
            minX: Double(minX),
            minY: Double(minY),
            maxX: Double(maxX),
            maxY: Double(maxY)
        )
    }
}
