// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import BezierTraceCore

final class SmallContourTests: XCTestCase {
    private func ellipse(_ rx: Double, _ ry: Double, count: Int = 80) -> [Point2D] {
        (0..<count).map { i in
            let t = Double(i) * 2 * .pi / Double(count)
            return Point2D(x: 100 + rx * cos(t), y: 100 + ry * sin(t))
        }
    }

    func testClosedFitDoesNotCollapseCoincidentEndpoints() throws {
        for radii in [(6.0, 6.0), (12, 4), (40, 2)] {
            let samples = ellipse(radii.0, radii.1)
            let fit = ContourFitter.fitClosed(smoothed: samples, accuracy: 0.5)
            XCTAssertEqual(fit, ContourFitter.fitClosed(smoothed: samples, accuracy: 0.5))
            XCTAssertTrue(fit.segments.allSatisfy { $0.start.distance(to: $0.end) > 1e-9 })
            let path = BezierPathContour(fit)
            XCTAssertGreaterThan(abs(CleanupDirection.signedArea(path)), radii.0 * radii.1 * 2.5)
            let fittedSamples = fit.segments.flatMap { curve in
                (0...200).map { curve.point(at: Double($0) / 200) }
            }
            for sample in samples {
                let error = try XCTUnwrap(fittedSamples.map { $0.distance(to: sample) }.min())
                XCTAssertLessThanOrEqual(error, 0.6, "Fitting error, including sampling tolerance")
            }
            _ = try OutlineValidator.validate(paths: CleanupDirection.fixDirections([path]))
        }
    }

    func testSmallCircleSurvivesPlanningAndFitting() throws {
        for radius in [5.5, 6, 8, 10] {
            let contour = SubpixelContour(points: ellipse(radius, radius))
            let outcome = ContourPlanner.plan(contour: contour, configuration: .capturedDefaults, raster: nil)
            let samples: [Point2D]
            let fit: FittedContour
            switch outcome {
            case .tooSmall: return XCTFail("Circle should have enough samples")
            case .noSplits(let points):
                samples = points; fit = ContourFitter.fitClosed(smoothed: points, accuracy: 0.5)
            case .plan(let plan):
                samples = plan.smoothed; fit = ContourFitter.fitInitial(plan: plan, accuracy: 0.5)
            }
            XCTAssertGreaterThan(abs(signedArea(of: samples)), .pi * radius * radius * 0.8)
            let path = BezierPathContour(fit)
            XCTAssertGreaterThan(abs(CleanupDirection.signedArea(path)), .pi * radius * radius * 0.7)
            _ = try OutlineValidator.validate(paths: CleanupDirection.fixDirections([path]))
        }
    }

    func testTwoCubicLoopAreaAndCounterDirection() throws {
        // Two cubic arches enclose area even though their endpoint polygon does not.
        let a = Point2D(x: 0, y: 0), b = Point2D(x: 20, y: 0)
        let outer = BezierPathContour(segments: [
            PathSegment(cubic: CubicBezier(start: a, control1: .init(x: 0, y: -10),
                control2: .init(x: 20, y: -10), end: b), isLine: false),
            PathSegment(cubic: CubicBezier(start: b, control1: .init(x: 20, y: 10),
                control2: .init(x: 0, y: 10), end: a), isLine: false),
        ])
        XCTAssertEqual(CleanupDirection.signedArea(outer), 240, accuracy: 1e-9)
        XCTAssertEqual(CleanupDirection.signedArea(CleanupDirection.reversed(outer)), -240, accuracy: 1e-9)
        _ = try OutlineValidator.validate(paths: [outer])
        let inner = BezierPathContour(ContourFitter.fitClosed(smoothed: ellipse(2, 2).map {
            Point2D(x: $0.x - 90, y: $0.y - 100)
        }, accuracy: 0.1))
        let directed = CleanupDirection.fixDirections([outer, inner])
        XCTAssertLessThan(CleanupDirection.signedArea(directed[1]), 0)
        _ = try OutlineValidator.validate(paths: directed)
    }

    func testSyntheticDotsTraceDeterministicallyAndRespectAreaFilter() throws {
        let data = try dotsImage()
        let extracted = try ContourPipeline.extract(data: data)
        XCTAssertEqual(extracted.contours.count, 5)
        let first = try BezierTracer.trace(.init(imageData: data))
        let second = try BezierTracer.trace(.init(imageData: data))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.outline.contours.count, extracted.contours.count)
        // The radius-2 and radius-5.5 dots remain below the existing minimum area.
        XCTAssertEqual(first.outline.contours.count, 5)
    }

    func testCollapsedLinesRemainInvalid() {
        let a = Point2D(x: 1, y: 2), b = Point2D(x: 5, y: 2)
        let path = BezierPathContour(segments: [
            PathSegment(cubic: lineCubic(from: a, to: b), isLine: true),
            PathSegment(cubic: lineCubic(from: b, to: a), isLine: true),
        ])
        XCTAssertEqual(CleanupDirection.signedArea(path), 0)
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [path]))
    }

    private func dotsImage() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1088, height: 1088,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1088, height: 1088))
        context.setFillColor(CGColor(gray: 0.35, alpha: 1))
        for (i, radius) in [5.5, 6.0, 8, 12, 18, 30, 2].enumerated() {
            context.fillEllipse(in: CGRect(x: Double(100 + i * 100), y: 300, width: radius * 2, height: radius * 2))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
