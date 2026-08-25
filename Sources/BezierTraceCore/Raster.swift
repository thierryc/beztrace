// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace. Image decoding uses
// Apple system frameworks instead of img2bez's Rust image dependencies.

import CoreGraphics
import Foundation
import ImageIO

enum ImageFormat: String, Equatable, Sendable {
    case png
    case jpeg
}

enum ThresholdMethod: Equatable, Sendable {
    case otsu
    case fixed(UInt8)
}

struct RasterPreparationOptions: Equatable, Sendable {
    var threshold: ThresholdMethod
    var invert: Bool
    var targetHeight: Double
    var minimumContourArea: Double
    var collapseBlockedScale: Bool
    var recoverLowResolution: Bool

    init(
        threshold: ThresholdMethod = .otsu,
        invert: Bool = false,
        targetHeight: Double = 1088,
        minimumContourArea: Double = 100,
        collapseBlockedScale: Bool = true,
        recoverLowResolution: Bool = true
    ) {
        self.threshold = threshold
        self.invert = invert
        self.targetHeight = targetHeight
        self.minimumContourArea = minimumContourArea
        self.collapseBlockedScale = collapseBlockedScale
        self.recoverLowResolution = recoverLowResolution
    }
}

struct GrayRaster: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw CoreError.invalidDimensions(width: width, height: height)
        }
        let (expected, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw CoreError.invalidDimensions(width: width, height: height)
        }
        guard pixels.count == expected else {
            throw CoreError.invalidPixelStorage(expected: expected, actual: pixels.count)
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func pixel(x: Int, y: Int) -> UInt8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return pixels[y * width + x]
    }
}

struct PreparedRaster: Equatable, Sendable {
    let raster: GrayRaster
    let threshold: UInt8
    let invert: Bool
    let sourceFormat: ImageFormat
    let usedAlphaMask: Bool
    let didCollapseBlockedScale: Bool
    let didUpscaleLowResolution: Bool
}

enum RasterPreparer {
    static let maximumEncodedBytes = 16 * 1024 * 1024
    static let maximumDimension = 4096

    private static let lowResolutionMaximumExtent = 200
    private static let lowResolutionTargetExtent = 400
    private static let lowResolutionMaximumFactor = 8.0

    static func prepare(
        data: Data,
        options: RasterPreparationOptions = RasterPreparationOptions()
    ) throws -> PreparedRaster {
        guard !data.isEmpty else { throw CoreError.emptyInput }
        guard data.count <= maximumEncodedBytes else {
            throw CoreError.encodedInputTooLarge(actual: data.count, limit: maximumEncodedBytes)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            throw CoreError.malformedImage
        }
        let format = try imageFormat(source: source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            throw CoreError.malformedImage
        }
        guard width <= maximumDimension, height <= maximumDimension else {
            throw CoreError.decodedImageTooLarge(
                width: width,
                height: height,
                limit: maximumDimension
            )
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw CoreError.malformedImage
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let decoded = try decode(image: image, orientation: orientation)
        return try prepare(
            raster: decoded.raster,
            sourceFormat: format,
            usedAlphaMask: decoded.usedAlphaMask,
            options: options
        )
    }

    static func prepare(
        raster: GrayRaster,
        sourceFormat: ImageFormat,
        usedAlphaMask: Bool,
        options: RasterPreparationOptions
    ) throws -> PreparedRaster {
        var prepared = raster
        var collapsed = false
        if options.collapseBlockedScale {
            while let downscaled = collapseUniformTwoByTwoBlocks(prepared) {
                prepared = downscaled
                collapsed = true
            }
        }
        var upscaled = false
        if options.recoverLowResolution,
           let recovered = upscaleLowResolution(prepared)
        {
            prepared = recovered
            upscaled = true
        }
        return PreparedRaster(
            raster: prepared,
            threshold: resolveThreshold(in: prepared, method: options.threshold),
            invert: options.invert,
            sourceFormat: sourceFormat,
            usedAlphaMask: usedAlphaMask,
            didCollapseBlockedScale: collapsed,
            didUpscaleLowResolution: upscaled
        )
    }

    static func resolveThreshold(in raster: GrayRaster, method: ThresholdMethod) -> UInt8 {
        switch method {
        case .fixed(let value):
            return value
        case .otsu:
            var histogram = Array(repeating: 0, count: 256)
            for pixel in raster.pixels {
                histogram[Int(pixel)] += 1
            }
            let total = raster.pixels.count
            var weightedTotal = 0.0
            for value in 0..<256 {
                weightedTotal += Double(value * histogram[value])
            }
            var backgroundCount = 0
            var backgroundWeighted = 0.0
            var maximumVariance = -Double.infinity
            var selected = 0
            for value in 0..<256 {
                backgroundCount += histogram[value]
                guard backgroundCount > 0 else { continue }
                let foregroundCount = total - backgroundCount
                guard foregroundCount > 0 else { break }
                backgroundWeighted += Double(value * histogram[value])
                let backgroundMean = backgroundWeighted / Double(backgroundCount)
                let foregroundMean = (weightedTotal - backgroundWeighted) / Double(foregroundCount)
                let delta = backgroundMean - foregroundMean
                let variance = Double(backgroundCount) * Double(foregroundCount) * delta * delta
                if variance > maximumVariance {
                    maximumVariance = variance
                    selected = value
                }
            }
            return UInt8(selected)
        }
    }

    private static func imageFormat(source: CGImageSource) throws -> ImageFormat {
        guard let type = CGImageSourceGetType(source) as String? else {
            throw CoreError.malformedImage
        }
        switch type {
        case "public.png":
            return .png
        case "public.jpeg":
            return .jpeg
        default:
            throw CoreError.unsupportedImageFormat(type)
        }
    }

    private static func decode(image: CGImage, orientation: Int) throws -> (raster: GrayRaster, usedAlphaMask: Bool) {
        let width = image.width
        let height = image.height
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else { throw CoreError.pixelBufferAllocationFailed }
        var rgba = Array(repeating: UInt8(0), count: byteCount)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let context = rgba.withUnsafeMutableBytes { bytes -> CGContext? in
            guard let base = bytes.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }
        guard let context else { throw CoreError.pixelBufferAllocationFailed }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let oriented = orientRGBA(rgba, width: width, height: height, orientation: orientation)
        let usedAlphaMask = stride(from: 3, to: oriented.pixels.count, by: 4)
            .contains { oriented.pixels[$0] < 255 }
        var luma = Array(repeating: UInt8(0), count: oriented.width * oriented.height)
        for index in luma.indices {
            let offset = index * 4
            if usedAlphaMask {
                luma[index] = 255 - oriented.pixels[offset + 3]
            } else {
                let red = Double(oriented.pixels[offset])
                let green = Double(oriented.pixels[offset + 1])
                let blue = Double(oriented.pixels[offset + 2])
                let value = (0.299 * red + 0.587 * green + 0.114 * blue)
                    .rounded(.toNearestOrAwayFromZero)
                luma[index] = UInt8(clamping: Int(value))
            }
        }
        return (
            try GrayRaster(width: oriented.width, height: oriented.height, pixels: luma),
            usedAlphaMask
        )
    }

    private static func orientRGBA(
        _ source: [UInt8],
        width: Int,
        height: Int,
        orientation: Int
    ) -> (pixels: [UInt8], width: Int, height: Int) {
        let swapsAxes = (5...8).contains(orientation)
        let outputWidth = swapsAxes ? height : width
        let outputHeight = swapsAxes ? width : height
        var output = Array(repeating: UInt8(0), count: source.count)
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let sourceCoordinate: (x: Int, y: Int)
                switch orientation {
                case 2: sourceCoordinate = (width - 1 - x, y)
                case 3: sourceCoordinate = (width - 1 - x, height - 1 - y)
                case 4: sourceCoordinate = (x, height - 1 - y)
                case 5: sourceCoordinate = (y, x)
                case 6: sourceCoordinate = (y, height - 1 - x)
                case 7: sourceCoordinate = (width - 1 - y, height - 1 - x)
                case 8: sourceCoordinate = (width - 1 - y, x)
                default: sourceCoordinate = (x, y)
                }
                let sourceOffset = (sourceCoordinate.y * width + sourceCoordinate.x) * 4
                let destinationOffset = (y * outputWidth + x) * 4
                output[destinationOffset..<(destinationOffset + 4)] = source[sourceOffset..<(sourceOffset + 4)]
            }
        }
        return (output, outputWidth, outputHeight)
    }

    private static func collapseUniformTwoByTwoBlocks(_ raster: GrayRaster) -> GrayRaster? {
        let width = raster.width
        let height = raster.height
        guard width >= 64, height >= 64, width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            return nil
        }
        let total = (width / 2) * (height / 2)
        var uniform = 0
        for blockY in 0..<(height / 2) {
            for blockX in 0..<(width / 2) {
                let x = blockX * 2
                let y = blockY * 2
                let values = [
                    raster.pixels[y * width + x],
                    raster.pixels[y * width + x + 1],
                    raster.pixels[(y + 1) * width + x],
                    raster.pixels[(y + 1) * width + x + 1],
                ]
                if Int(values.max()!) - Int(values.min()!) <= 2 {
                    uniform += 1
                }
            }
        }
        guard uniform >= total - total / 2000 else { return nil }
        var pixels = Array(repeating: UInt8(0), count: total)
        for y in 0..<(height / 2) {
            for x in 0..<(width / 2) {
                pixels[y * (width / 2) + x] = raster.pixels[(y * 2) * width + x * 2]
            }
        }
        return try? GrayRaster(width: width / 2, height: height / 2, pixels: pixels)
    }

    private static func upscaleLowResolution(_ raster: GrayRaster) -> GrayRaster? {
        guard let bounds = inkBounds(raster) else { return nil }
        let extent = max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
        guard extent > 0, extent < lowResolutionMaximumExtent else { return nil }
        let factor = min(
            ceil(Double(lowResolutionTargetExtent) / Double(extent)),
            lowResolutionMaximumFactor
        )
        guard factor >= 2 else { return nil }
        let width = max(1, Int((Double(raster.width) * factor).rounded()))
        let height = max(1, Int((Double(raster.height) * factor).rounded()))
        return resizeCatmullRom(raster, width: width, height: height)
    }

    private static func inkBounds(_ raster: GrayRaster) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        let corners = [
            raster.pixels[0],
            raster.pixels[raster.width - 1],
            raster.pixels[(raster.height - 1) * raster.width],
            raster.pixels[raster.pixels.count - 1],
        ]
        let background = corners.reduce(0) { $0 + Int($1) } / corners.count
        var minX = raster.width
        var minY = raster.height
        var maxX = 0
        var maxY = 0
        var found = false
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                if abs(Int(raster.pixels[y * raster.width + x]) - background) > 40 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    found = true
                }
            }
        }
        return found ? (minX, minY, maxX, maxY) : nil
    }

    private static func resizeCatmullRom(_ raster: GrayRaster, width: Int, height: Int) -> GrayRaster? {
        var output = Array(repeating: UInt8(0), count: width * height)
        let scaleX = Double(raster.width) / Double(width)
        let scaleY = Double(raster.height) / Double(height)
        for destinationY in 0..<height {
            let sourceY = (Double(destinationY) + 0.5) * scaleY - 0.5
            let baseY = Int(floor(sourceY))
            for destinationX in 0..<width {
                let sourceX = (Double(destinationX) + 0.5) * scaleX - 0.5
                let baseX = Int(floor(sourceX))
                var value = 0.0
                var weightSum = 0.0
                for sampleY in (baseY - 1)...(baseY + 2) {
                    let weightY = catmullRomWeight(sourceY - Double(sampleY))
                    let clampedY = min(max(sampleY, 0), raster.height - 1)
                    for sampleX in (baseX - 1)...(baseX + 2) {
                        let weight = weightY * catmullRomWeight(sourceX - Double(sampleX))
                        let clampedX = min(max(sampleX, 0), raster.width - 1)
                        value += Double(raster.pixels[clampedY * raster.width + clampedX]) * weight
                        weightSum += weight
                    }
                }
                let normalized = weightSum == 0 ? 0 : value / weightSum
                output[destinationY * width + destinationX] = UInt8(
                    clamping: Int(normalized.rounded(.toNearestOrAwayFromZero))
                )
            }
        }
        return try? GrayRaster(width: width, height: height, pixels: output)
    }

    private static func catmullRomWeight(_ distance: Double) -> Double {
        let x = abs(distance)
        if x <= 1 {
            return 1.5 * x * x * x - 2.5 * x * x + 1
        }
        if x < 2 {
            return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2
        }
        return 0
    }
}
