// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class RasterRefinementTests: XCTestCase {
    private struct PreparedMetadata: Decodable {
        struct Options: Decodable { let emHeight: Double }
        let threshold: UInt8
        let invert: Bool
        let height: Int
        let options: Options
    }

    private struct StructuralPlanStage: Decodable {
        struct Sample: Decodable { let x: Double; let y: Double }
        struct Split: Decodable { let index: Int; let kind: String }
        let contourIndex: Int
        let smoothed: [Sample]
        let splits: [Split]
        let lineSections: [[Int]]
    }

    private struct OutlineStage: Decodable {
        struct Path: Decodable { let elements: [Element] }
        struct Element: Decodable {
            let type: String
            let x: Double?
            let y: Double?
            let points: [[Double]]?
        }
        let contourIndex: Int
        let path: Path
    }

    func testSignedDistanceFollowsTravelDirection() {
        let line = [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)]
        XCTAssertGreaterThan(ContourRefiner.signedDistance(Point2D(x: 5, y: 1), to: line), 0)
        XCTAssertLessThan(ContourRefiner.signedDistance(Point2D(x: 5, y: -1), to: line), 0)
        XCTAssertEqual(
            ContourRefiner.signedDistance(Point2D(x: 5, y: 2), to: line),
            2,
            accuracy: 1e-9
        )
    }

    func testRasterWithoutGradientReturnsUnrefinedFit() throws {
        let raster = try GrayRaster(width: 16, height: 16, pixels: Array(repeating: 255, count: 256))
        let target = RasterTarget(raster: raster, invert: false, pixelsPerUnit: 1)
        let points = [
            Point2D(x: 2, y: 2), Point2D(x: 14, y: 2),
            Point2D(x: 14, y: 14), Point2D(x: 2, y: 14),
        ]
        let contour = FittedContour(
            segments: points.indices.map { lineCubic(from: points[$0], to: points[($0 + 1) % points.count]) },
            isLine: Array(repeating: true, count: points.count),
            jointKinds: Array(repeating: .corner, count: points.count)
        )
        XCTAssertEqual(ContourRefiner.refine(contour, raster: target), contour)
    }

    func testFocusedRasterRefinedFitsMatchPinnedOracle() throws {
        let identifiers = ["uni0061", "uni0065", "uni0073", "uni0052", "uni004F", "uni0053", "uni006E"]
        for identifier in identifiers { try assertRefinedFitsMatchOracle(identifier: identifier) }
    }

    func testAllBasicLatinRasterRefinedFitsMatchPinnedOracle() throws {
        let root = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
        let identifiers = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent.hasPrefix("uni") }
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(identifiers.count, 62)
        for identifier in identifiers { try assertRefinedFitsMatchOracle(identifier: identifier) }
    }

    func testHandleOptimizationRecoversQuarterCircleTension() throws {
        let size = 64
        var pixels: [UInt8] = []
        pixels.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let distance = hypot(Double(x) + 0.5 - 32, Double(y) + 0.5 - 32)
                pixels.append(UInt8(min(max(distance - 20 + 0.5, 0), 1) * 255))
            }
        }
        let target = RasterTarget(
            raster: try GrayRaster(width: size, height: size, pixels: pixels),
            invert: false,
            pixelsPerUnit: 1
        )
        let start = Point2D(x: 52, y: 32)
        let end = Point2D(x: 32, y: 52)
        let expectedHandle = 0.5523 * 20
        let reference = CubicBezier(
            start: start,
            control1: Point2D(x: 52, y: 32 + expectedHandle),
            control2: Point2D(x: 32 + expectedHandle, y: 52),
            end: end
        )
        let band = ContourRefiner.collectBand(
            raster: target,
            region: ContourRefiner.sampleCubic(reference),
            fixed: []
        )
        let optimized = ContourRefiner.optimizeHandles(
            start: start,
            startDirection: Vector2D(dx: 0, dy: 1),
            endDirection: Vector2D(dx: 1, dy: 0),
            end: end,
            initial: (3, 3),
            band: band,
            inkLeft: true
        )
        XCTAssertEqual(optimized.segment.start.distance(to: optimized.segment.control1), expectedHandle, accuracy: 1.2)
        XCTAssertEqual(optimized.segment.end.distance(to: optimized.segment.control2), expectedHandle, accuracy: 1.2)
    }

    private func assertRefinedFitsMatchOracle(identifier: String) throws {
        let directory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(
            PreparedMetadata.self,
            from: Data(contentsOf: directory.appendingPathComponent("prepared-raster.json"))
        )
        let prepared = try RasterPreparer.prepare(
            data: Data(contentsOf: directory.appendingPathComponent("prepared-raster.png")),
            options: .init(
                threshold: .fixed(metadata.threshold), invert: metadata.invert, recoverLowResolution: false
            )
        )
        let scale = metadata.options.emHeight / Double(metadata.height)
        let accuracy = min(max(TraceConfiguration.capturedDefaults.fitAccuracy / scale, 0.5), 3)
        let raster = RasterTarget(raster: prepared.raster, invert: metadata.invert, pixelsPerUnit: 1 / scale)
        let stageURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("raster-refined-") }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        for stageURL in stageURLs {
            let expected = try decoder.decode(OutlineStage.self, from: Data(contentsOf: stageURL))
            let suffix = String(format: "%03d", expected.contourIndex)
            let structural = try decoder.decode(
                StructuralPlanStage.self,
                from: Data(contentsOf: directory.appendingPathComponent("structural-plan-\(suffix).json"))
            )
            let plan = ContourPlan(
                smoothed: structural.smoothed.map { Point2D(x: $0.x, y: $0.y) },
                splits: try structural.splits.map {
                    StructuralSplit(index: $0.index, kind: try splitKind(named: $0.kind))
                },
                lineSections: try structural.lineSections.map {
                    guard $0.count == 2 else { throw DecodeFailure.invalidLineSection }
                    return LineSection(start: $0[0], end: $0[1])
                }
            )
            let initial = ContourFitter.fitInitial(plan: plan, accuracy: accuracy)
            let actual = ContourRefiner.refine(initial, raster: raster).pathElements
            try assertPath(actual, matches: expected.path.elements, tolerance: 0.25 / scale, identifier: identifier)
        }
    }

    private func assertPath(
        _ actual: [InternalPathElement],
        matches expected: [OutlineStage.Element],
        tolerance: Double,
        identifier: String
    ) throws {
        XCTAssertEqual(actual.count, expected.count, identifier)
        guard actual.count == expected.count else { return }
        for (element, oracle) in zip(actual, expected) {
            switch (element, oracle.type) {
            case (.move(let point), "move"), (.line(let point), "line"):
                XCTAssertEqual(point.x, try XCTUnwrap(oracle.x), accuracy: tolerance, identifier)
                XCTAssertEqual(point.y, try XCTUnwrap(oracle.y), accuracy: tolerance, identifier)
            case (.curve(let control1, let control2, let end), "curve"):
                let points = try XCTUnwrap(oracle.points)
                XCTAssertEqual(points.count, 3, identifier)
                guard points.count == 3 else { continue }
                for (point, pair) in zip([control1, control2, end], points) {
                    XCTAssertEqual(point.x, pair[0], accuracy: tolerance, identifier)
                    XCTAssertEqual(point.y, pair[1], accuracy: tolerance, identifier)
                }
            case (.close, "close"):
                break
            default:
                XCTFail("\(identifier) path topology differs: \(element) vs \(oracle.type)")
            }
        }
    }

    private enum DecodeFailure: Error { case invalidSplitKind(String); case invalidLineSection }

    private func splitKind(named name: String) throws -> SplitKind {
        switch name {
        case "Corner": .corner
        case "Tangent": .tangent
        case "ExtremumX": .extremumX
        case "ExtremumY": .extremumY
        case "Inflection": .inflection
        case "FitterJoint": .fitterJoint
        default: throw DecodeFailure.invalidSplitKind(name)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
