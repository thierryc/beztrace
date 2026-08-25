// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import XCTest
@testable import BezierTraceCore

final class SubpixelContourTests: XCTestCase {
    func testAllMarchingSquareCasesAndAmbiguousSaddles() {
        XCTAssertEqual(SubpixelExtractor.segments(for: 0, centerInside: false), [])
        XCTAssertEqual(SubpixelExtractor.segments(for: 15, centerInside: true), [])
        XCTAssertEqual(SubpixelExtractor.segments(for: 1, centerInside: false), [
            CellSegment(.top, .left),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 2, centerInside: false), [
            CellSegment(.top, .right),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 3, centerInside: false), [
            CellSegment(.left, .right),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 4, centerInside: false), [
            CellSegment(.left, .bottom),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 5, centerInside: false), [
            CellSegment(.top, .bottom),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 7, centerInside: false), [
            CellSegment(.right, .bottom),
        ])
        for code in [11, 12, 13, 14] {
            XCTAssertEqual(
                SubpixelExtractor.segments(for: UInt8(code), centerInside: false),
                SubpixelExtractor.segments(for: UInt8(15 - code), centerInside: false)
            )
        }
        XCTAssertEqual(SubpixelExtractor.segments(for: 6, centerInside: true), [
            CellSegment(.top, .left), CellSegment(.right, .bottom),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 6, centerInside: false), [
            CellSegment(.top, .right), CellSegment(.left, .bottom),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 9, centerInside: true), [
            CellSegment(.top, .right), CellSegment(.left, .bottom),
        ])
        XCTAssertEqual(SubpixelExtractor.segments(for: 9, centerInside: false), [
            CellSegment(.top, .left), CellSegment(.right, .bottom),
        ])
    }

    func testAntialiasedDiskHasAccurateClosedContour() throws {
        let width = 64
        let height = 64
        let pixels = (0..<height).flatMap { y in
            (0..<width).map { x -> UInt8 in
                let distance = hypot(Double(x) + 0.5 - 32, Double(y) + 0.5 - 32)
                let coverage = min(max(distance - 20 + 0.5, 0), 1)
                return UInt8(coverage * 255)
            }
        }
        let raster = try GrayRaster(width: width, height: height, pixels: pixels)
        let contours = SubpixelExtractor.extract(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 16
        )

        XCTAssertEqual(contours.count, 1)
        let contour = try XCTUnwrap(contours.first)
        XCTAssertGreaterThanOrEqual(contour.points.count, 8)
        XCTAssertTrue(contour.isFinite)
        for point in contour.points {
            let radius = hypot(point.x - 32, point.y - 32)
            XCTAssertLessThan(abs(radius - 20), 0.35)
        }
    }

    func testBorderTouchingRectangleRemainsClosed() throws {
        let raster = try GrayRaster(
            width: 20,
            height: 20,
            pixels: (0..<20).flatMap { _ in (0..<20).map { $0 < 10 ? 0 : 255 } }
        )
        let contours = SubpixelExtractor.extract(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 4
        )

        XCTAssertEqual(contours.count, 1)
        XCTAssertGreaterThanOrEqual(contours[0].points.count, 8)
        XCTAssertNotEqual(contours[0].winding, .degenerate)
    }

    func testRingProducesOuterAndCounter() throws {
        let raster = try GrayRaster(
            width: 64,
            height: 64,
            pixels: (0..<64).flatMap { y in
                (0..<64).map { x -> UInt8 in
                    let distance = hypot(Double(x) - 32, Double(y) - 32)
                    return distance > 8 && distance < 16 ? 0 : 255
                }
            }
        )
        let contours = SubpixelExtractor.extract(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 16
        )

        XCTAssertEqual(contours.count, 2)
        // The pinned extraction stage preserves traversal order; typographic
        // outer/counter direction normalization is a later pipeline pass.
        XCTAssertEqual(Set(contours.map(\.winding)), [.clockwise])
    }

    func testLinearInterpolationFindsHalfPixelRamp() throws {
        let raster = try GrayRaster(
            width: 20,
            height: 20,
            pixels: (0..<20).flatMap { _ in (0..<20).map { $0 < 10 ? 0 : 255 } }
        )
        let contour = try XCTUnwrap(SubpixelExtractor.extract(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 4
        ).first)

        XCTAssertTrue(contour.points.contains { abs($0.x - 10) < 1e-12 && $0.y > 2 && $0.y < 18 })
    }

    func testSpecklesAndFrameArtifactsAreFiltered() throws {
        var pixels = Array(repeating: UInt8(255), count: 64 * 64)
        for index in 0..<64 {
            pixels[index] = 0
            pixels[(63 * 64) + index] = 0
            pixels[index * 64] = 0
            pixels[index * 64 + 63] = 0
        }
        for y in 24..<40 {
            for x in 24..<40 { pixels[y * 64 + x] = 0 }
        }
        pixels[10 * 64 + 10] = 0
        let raster = try GrayRaster(width: 64, height: 64, pixels: pixels)
        let contours = SubpixelExtractor.glyphContours(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 4
        )

        XCTAssertEqual(contours.count, 1)
        XCTAssertEqual(contours[0].bounds, Bounds(minX: 24, minY: 24, maxX: 40, maxY: 40))
    }

    func testExtractionIsExactlyDeterministic() throws {
        let raster = try GrayRaster(
            width: 32,
            height: 32,
            pixels: (0..<32).flatMap { y in
                (0..<32).map { x in (x > 5 && x < 26 && y > 7 && y < 24) ? 0 : 255 }
            }
        )
        let first = SubpixelExtractor.extract(
            raster: raster,
            threshold: 127,
            invert: false,
            minimumAreaPixels: 2
        )
        for _ in 0..<10 {
            XCTAssertEqual(
                SubpixelExtractor.extract(
                    raster: raster,
                    threshold: 127,
                    invert: false,
                    minimumAreaPixels: 2
                ),
                first
            )
        }
    }
}
