// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import BezierTraceCore

final class RasterPreparationTests: XCTestCase {
    func testGrayRasterValidatesDimensionsAndStorage() throws {
        XCTAssertThrowsError(try GrayRaster(width: 0, height: 1, pixels: [])) { error in
            XCTAssertEqual(error as? CoreError, .invalidDimensions(width: 0, height: 1))
        }
        XCTAssertThrowsError(try GrayRaster(width: 2, height: 2, pixels: [0, 1, 2])) { error in
            XCTAssertEqual(error as? CoreError, .invalidPixelStorage(expected: 4, actual: 3))
        }

        let raster = try GrayRaster(width: 2, height: 2, pixels: [1, 2, 3, 4])
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 1)
        XCTAssertEqual(raster.pixel(x: 1, y: 1), 4)
        XCTAssertNil(raster.pixel(x: -1, y: 0))
        XCTAssertNil(raster.pixel(x: 2, y: 0))
    }

    func testOpaqueRGBUsesDeterministicLuma() throws {
        let png = try encodedImage(
            width: 3,
            height: 1,
            rgba: [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]
        )
        let result = try RasterPreparer.prepare(
            data: png,
            options: .init(threshold: .fixed(127), recoverLowResolution: false)
        )

        XCTAssertEqual(result.sourceFormat, .png)
        XCTAssertFalse(result.usedAlphaMask)
        XCTAssertEqual(result.raster.pixels, [76, 150, 29])
        XCTAssertEqual(result.threshold, 127)
    }

    func testAnyTransparencyUsesAlphaCoverage() throws {
        let png = try encodedImage(
            width: 3,
            height: 1,
            rgba: [200, 100, 50, 255, 0, 0, 0, 128, 255, 255, 255, 0]
        )
        let result = try RasterPreparer.prepare(
            data: png,
            options: .init(threshold: .fixed(127), recoverLowResolution: false)
        )

        XCTAssertTrue(result.usedAlphaMask)
        XCTAssertEqual(result.raster.pixels, [0, 127, 255])
    }

    func testAllImageOrientationsNormalizeToTopDownRows() throws {
        let values: [UInt8] = [10, 20, 30, 40, 50, 60]
        let rgba = values.flatMap { [$0, $0, $0, UInt8(255)] }
        let expected: [(orientation: Int, width: Int, height: Int, pixels: [UInt8])] = [
            (1, 2, 3, [10, 20, 30, 40, 50, 60]),
            (2, 2, 3, [20, 10, 40, 30, 60, 50]),
            (3, 2, 3, [60, 50, 40, 30, 20, 10]),
            (4, 2, 3, [50, 60, 30, 40, 10, 20]),
            (5, 3, 2, [10, 30, 50, 20, 40, 60]),
            (6, 3, 2, [50, 30, 10, 60, 40, 20]),
            (7, 3, 2, [60, 40, 20, 50, 30, 10]),
            (8, 3, 2, [20, 40, 60, 10, 30, 50]),
        ]
        for item in expected {
            let png = try encodedImage(width: 2, height: 3, rgba: rgba, orientation: item.orientation)
            let result = try RasterPreparer.prepare(
                data: png,
                options: .init(threshold: .fixed(127), recoverLowResolution: false)
            )
            XCTAssertEqual(result.raster.width, item.width, "orientation \(item.orientation)")
            XCTAssertEqual(result.raster.height, item.height, "orientation \(item.orientation)")
            XCTAssertEqual(result.raster.pixels, item.pixels, "orientation \(item.orientation)")
        }
    }

    func testJPEGIsAcceptedAndUnsupportedImageTypeIsRejected() throws {
        let black: [UInt8] = [0, 0, 0, 255]
        let pixels = Array(repeating: black, count: 64).flatMap { $0 }
        let jpeg = try encodedImage(width: 8, height: 8, rgba: pixels, type: "public.jpeg")
        let result = try RasterPreparer.prepare(
            data: jpeg,
            options: .init(threshold: .fixed(127), recoverLowResolution: false)
        )
        XCTAssertEqual(result.sourceFormat, .jpeg)
        XCTAssertEqual(result.raster.width, 8)
        XCTAssertEqual(result.raster.height, 8)
        XCTAssertFalse(result.usedAlphaMask)
        XCTAssertTrue(result.raster.pixels.allSatisfy { $0 <= 2 })

        let tiff = try encodedImage(width: 1, height: 1, rgba: [0, 0, 0, 255], type: "public.tiff")
        XCTAssertThrowsError(try RasterPreparer.prepare(data: tiff)) { error in
            XCTAssertEqual(error as? CoreError, .unsupportedImageFormat("public.tiff"))
        }
    }

    func testOtsuUsesFirstMaximumAndFixedThresholdRoundTrips() throws {
        let raster = try GrayRaster(width: 2, height: 2, pixels: [0, 0, 255, 255])

        XCTAssertEqual(RasterPreparer.resolveThreshold(in: raster, method: .otsu), 0)
        XCTAssertEqual(RasterPreparer.resolveThreshold(in: raster, method: .fixed(203)), 203)
    }

    func testUniformTwoByTwoBlocksCollapseBeforeTracing() throws {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                pixels.append(UInt8(((x / 2 + y / 2) % 2) * 255))
            }
        }
        let raster = try GrayRaster(width: 64, height: 64, pixels: pixels)
        let result = try RasterPreparer.prepare(
            raster: raster,
            sourceFormat: .png,
            usedAlphaMask: false,
            options: .init(threshold: .fixed(127), recoverLowResolution: false)
        )

        XCTAssertTrue(result.didCollapseBlockedScale)
        XCTAssertEqual(result.raster.width, 32)
        XCTAssertEqual(result.raster.height, 32)
    }

    func testLowResolutionInkIsUpscaledWithBoundedFactor() throws {
        var pixels = Array(repeating: UInt8(255), count: 40 * 40)
        for y in 10..<30 {
            for x in 10..<30 {
                pixels[y * 40 + x] = x == 10 ? 32 : 0
            }
        }
        let raster = try GrayRaster(width: 40, height: 40, pixels: pixels)
        let result = try RasterPreparer.prepare(
            raster: raster,
            sourceFormat: .png,
            usedAlphaMask: false,
            options: .init(threshold: .fixed(127), collapseBlockedScale: false)
        )

        XCTAssertTrue(result.didUpscaleLowResolution)
        XCTAssertEqual(result.raster.width, 320)
        XCTAssertEqual(result.raster.height, 320)
        XCTAssertEqual(result.raster.pixels.count, 320 * 320)
    }

    func testLowResolutionRecoveryNeverExceedsDecodedDimensionLimit() throws {
        var pixels = Array(repeating: UInt8(255), count: RasterPreparer.maximumDimension * 64)
        for y in 20..<30 {
            for x in 20..<30 {
                pixels[y * RasterPreparer.maximumDimension + x] = 0
            }
        }
        let raster = try GrayRaster(
            width: RasterPreparer.maximumDimension,
            height: 64,
            pixels: pixels
        )
        let result = try RasterPreparer.prepare(
            raster: raster,
            sourceFormat: .png,
            usedAlphaMask: false,
            options: .init(threshold: .fixed(127), collapseBlockedScale: false)
        )

        XCTAssertFalse(result.didUpscaleLowResolution)
        XCTAssertEqual(result.raster.width, RasterPreparer.maximumDimension)
        XCTAssertEqual(result.raster.height, 64)
    }

    func testFullyTransparentImageProducesNoContours() throws {
        let transparent = try encodedImage(
            width: 32,
            height: 32,
            rgba: Array(repeating: UInt8(0), count: 32 * 32 * 4)
        )
        XCTAssertThrowsError(try ContourPipeline.extract(data: transparent)) { error in
            XCTAssertEqual(error as? CoreError, .noContours)
        }
    }

    func testInputAndDecodedDimensionLimitsFailClosed() throws {
        XCTAssertThrowsError(try RasterPreparer.prepare(data: Data())) { error in
            XCTAssertEqual(error as? CoreError, .emptyInput)
        }
        let oversized = Data(repeating: 0, count: RasterPreparer.maximumEncodedBytes + 1)
        XCTAssertThrowsError(try RasterPreparer.prepare(data: oversized)) { error in
            XCTAssertEqual(
                error as? CoreError,
                .encodedInputTooLarge(actual: oversized.count, limit: RasterPreparer.maximumEncodedBytes)
            )
        }
        XCTAssertThrowsError(try RasterPreparer.prepare(data: Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? CoreError, .malformedImage)
        }

        let tooWide = try encodedImage(
            width: RasterPreparer.maximumDimension + 1,
            height: 1,
            rgba: Array(repeating: 255, count: (RasterPreparer.maximumDimension + 1) * 4)
        )
        XCTAssertThrowsError(try RasterPreparer.prepare(data: tooWide)) { error in
            XCTAssertEqual(
                error as? CoreError,
                .decodedImageTooLarge(
                    width: RasterPreparer.maximumDimension + 1,
                    height: 1,
                    limit: RasterPreparer.maximumDimension
                )
            )
        }
    }

    private func encodedImage(
        width: Int,
        height: Int,
        rgba: [UInt8],
        orientation: Int = 1,
        type: String = "public.png"
    ) throws -> Data {
        XCTAssertEqual(rgba.count, width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData,
            type as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
