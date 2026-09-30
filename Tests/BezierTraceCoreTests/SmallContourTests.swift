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

    func testSmallConvexOvalsRemainCurvesAcrossPresets() throws {
        let data = try ovalsImage()
        let options = [
            TraceOptions(minimumContourArea: 0, accuracy: 2, smoothing: 1,
                         cornerThresholdDegrees: 12, grid: 2),
            TraceOptions(minimumContourArea: 0, accuracy: 1, smoothing: 0.7,
                         cornerThresholdDegrees: 10, grid: 1),
            TraceOptions(minimumContourArea: 0, accuracy: 0.75, smoothing: 1.5,
                         cornerThresholdDegrees: 30, grid: 0),
            TraceOptions(threshold: .fixed(160), minimumContourArea: 0, accuracy: 0.5,
                         smoothing: 3, cornerThresholdDegrees: 60, grid: 0),
        ]
        for option in options {
            let first = try BezierTracer.trace(.init(imageData: data, options: option))
            let second = try BezierTracer.trace(.init(imageData: data, options: option))
            let lineContours = first.outline.contours.enumerated().compactMap { index, contour in
                contour.nodes.contains(where: { $0.type == .line }) ? index : nil
            }
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.outline.contours.count, 4)
            XCTAssertEqual(first.statistics.lineCount, 0, "options: \(option), paths: \(lineContours)")
            XCTAssertTrue(first.outline.contours.allSatisfy { contour in
                contour.nodes.allSatisfy { $0.type != .line }
            }, "options: \(option), paths: \(lineContours)")
            XCTAssertTrue(first.outline.contours.allSatisfy { contour in
                contour.nodes.filter { $0.type != .offcurve }.count >= 3
            }, "options: \(option)")
        }
    }

    func testCurvatureProtectionExcludesIntentionalStructureAndLargeContours() throws {
        let shapes = [rectangle(), triangle(), roundedRectangle(), pill()]
        for points in shapes {
            let contour = SubpixelContour(points: points)
            guard case .plan(let plan) = ContourPlanner.plan(
                contour: contour,
                configuration: .capturedDefaults,
                raster: nil
            ) else { return XCTFail("Structured contour should produce a plan") }
            XCTAssertFalse(ContourFitter.isSmallConvexCandidate(plan: plan))
        }

        let large = SubpixelContour(points: ellipse(60, 45, count: 180))
        guard case .plan(let largePlan) = ContourPlanner.plan(
            contour: large,
            configuration: .capturedDefaults,
            raster: nil
        ) else { return XCTFail("Large ellipse should produce a plan") }
        XCTAssertFalse(ContourFitter.isSmallConvexCandidate(plan: largePlan))

        let concave = SubpixelContour(points: [
            .init(x: 0, y: 0), .init(x: 30, y: 0), .init(x: 30, y: 30),
            .init(x: 15, y: 12), .init(x: 0, y: 30),
        ])
        guard case .plan(let concavePlan) = ContourPlanner.plan(
            contour: concave,
            configuration: .capturedDefaults,
            raster: nil
        ) else { return XCTFail("Concave contour should produce a plan") }
        XCTAssertFalse(ContourFitter.isSmallConvexCandidate(plan: concavePlan))
    }

    func testTwoCubicLoopGainsAnOnCurveWithoutChangingGeometry() throws {
        // Two cubic arches enclose area even though their endpoint polygon does not.
        let a = Point2D(x: 0, y: 0), b = Point2D(x: 20, y: 0)
        let outer = BezierPathContour(segments: [
            PathSegment(cubic: CubicBezier(start: a, control1: .init(x: 0, y: -10),
                control2: .init(x: 20, y: -10), end: b), isLine: false),
            PathSegment(cubic: CubicBezier(start: b, control1: .init(x: 20, y: 18),
                control2: .init(x: 0, y: 18), end: a), isLine: false),
        ])
        let repaired = CleanupMinimumNodes.ensureThreeOnCurves(outer)
        let expectedHalves = outer.segments[1].cubic.split(at: 0.5)
        XCTAssertEqual(repaired.segments.count, 3)
        XCTAssertEqual(repaired.segments[0], outer.segments[0])
        XCTAssertEqual(repaired.segments[1].cubic, expectedHalves.0)
        XCTAssertEqual(repaired.segments[2].cubic, expectedHalves.1)
        XCTAssertTrue(repaired.segments.allSatisfy { !$0.isLine })
        XCTAssertEqual(
            CleanupDirection.signedArea(repaired),
            CleanupDirection.signedArea(outer),
            accuracy: 1e-9
        )
        for sample in 0...100 {
            let t = Double(sample) / 100
            let rebuilt = t <= 0.5
                ? repaired.segments[1].cubic.point(at: t * 2)
                : repaired.segments[2].cubic.point(at: (t - 0.5) * 2)
            let original = outer.segments[1].cubic.point(at: t)
            XCTAssertEqual(rebuilt.x, original.x, accuracy: 1e-9)
            XCTAssertEqual(rebuilt.y, original.y, accuracy: 1e-9)
        }
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [outer])) {
            XCTAssertEqual(
                $0 as? CoreError,
                .insufficientOnCurveNodes(contour: 0, actual: 2, minimum: 3)
            )
        }
        _ = try OutlineValidator.validate(paths: [repaired])
        let inner = BezierPathContour(ContourFitter.fitClosed(smoothed: ellipse(2, 2).map {
            Point2D(x: $0.x - 90, y: $0.y - 100)
        }, accuracy: 0.1))
        let directed = CleanupDirection.fixDirections([repaired, inner])
        XCTAssertLessThan(CleanupDirection.signedArea(directed[1]), 0)
        _ = try OutlineValidator.validate(paths: directed)
    }

    func testMinimumOnCurveRepairLeavesThreeAndLargerContoursUnchanged() {
        let triangle = BezierPathContour(segments: [
            PathSegment(cubic: lineCubic(from: .init(x: 0, y: 0), to: .init(x: 20, y: 0)), isLine: true),
            PathSegment(cubic: lineCubic(from: .init(x: 20, y: 0), to: .init(x: 10, y: 20)), isLine: true),
            PathSegment(cubic: lineCubic(from: .init(x: 10, y: 20), to: .init(x: 0, y: 0)), isLine: true),
        ])
        XCTAssertEqual(CleanupMinimumNodes.ensureThreeOnCurves(triangle), triangle)
        let four = BezierPathContour(ContourFitter.fitClosed(smoothed: ellipse(10, 8), accuracy: 0.5))
        XCTAssertGreaterThanOrEqual(four.segments.count, 4)
        XCTAssertEqual(CleanupMinimumNodes.ensureThreeOnCurves(four), four)
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
        XCTAssertEqual(CleanupMinimumNodes.ensureThreeOnCurves(path), path)
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [path]))

        let loop = BezierPathContour(segments: [
            PathSegment(cubic: CubicBezier(
                start: a,
                control1: .init(x: 2, y: 8),
                control2: .init(x: 4, y: 8),
                end: a
            ), isLine: false),
        ])
        XCTAssertEqual(CleanupMinimumNodes.ensureThreeOnCurves(loop), loop)
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [loop]))
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

    private func ovalsImage() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 240,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        context.setFillColor(CGColor(gray: 0.35, alpha: 1))
        let ovals: [(CGPoint, CGSize, CGFloat)] = [
            (.init(x: 55, y: 60), .init(width: 18, height: 30), 0),
            (.init(x: 135, y: 65), .init(width: 22, height: 36), .pi / 7),
            (.init(x: 220, y: 65), .init(width: 26, height: 42), -.pi / 9),
            (.init(x: 275, y: 160), .init(width: 18, height: 32), 0),
        ]
        for (center, size, rotation) in ovals {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation)
            context.fillEllipse(in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ))
            context.restoreGState()
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            bytes,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func rectangle() -> [Point2D] {
        [.init(x: 0, y: 0), .init(x: 50, y: 0), .init(x: 50, y: 30), .init(x: 0, y: 30)]
    }

    private func triangle() -> [Point2D] {
        [.init(x: 0, y: 0), .init(x: 50, y: 0), .init(x: 25, y: 45)]
    }

    private func roundedRectangle() -> [Point2D] {
        roundedBox(width: 70, height: 45, radius: 8)
    }

    private func pill() -> [Point2D] {
        roundedBox(width: 80, height: 24, radius: 12)
    }

    private func roundedBox(width: Double, height: Double, radius: Double) -> [Point2D] {
        let centers = [
            Point2D(x: width - radius, y: height - radius),
            Point2D(x: radius, y: height - radius),
            Point2D(x: radius, y: radius),
            Point2D(x: width - radius, y: radius),
        ]
        return centers.enumerated().flatMap { corner, center in
            (0...8).map { step in
                let start = Double(corner) * .pi / 2
                let angle = start + Double(step) * .pi / 16
                return Point2D(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
    }
}
