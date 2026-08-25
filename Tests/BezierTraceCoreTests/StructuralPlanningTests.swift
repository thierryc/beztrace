// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class StructuralPlanningTests: XCTestCase {
    private struct PreparedMetadata: Decodable {
        struct Options: Decodable { let emHeight: Double }
        let threshold: UInt8
        let invert: Bool
        let options: Options
    }

    private struct PlanStage: Decodable {
        struct Sample: Decodable { let x: Double; let y: Double }
        struct Split: Decodable { let index: Int; let kind: String }
        let contourIndex: Int
        let smoothed: [Sample]
        let splits: [Split]
        let lineSections: [[Int]]
    }

    func testClosedResamplingAndTurnsAreDeterministic() {
        let square = [
            Point2D(x: 0, y: 0), Point2D(x: 8, y: 0),
            Point2D(x: 8, y: 8), Point2D(x: 0, y: 8),
        ]
        let first = ContourPlanner.resampleClosed(square, spacing: 1)
        let second = ContourPlanner.resampleClosed(square, spacing: 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(ContourPlanner.vertexTurns(first).count, first.count)
        XCTAssertEqual(ContourPlanner.vertexTurns(first).reduce(0, +), 2 * .pi, accuracy: 1e-9)
    }

    func testFocusedStructuralPlansMatchPinnedOracle() throws {
        // The immutable Basic Latin stage capture contains the seven
        // alphanumeric smoke glyphs. Ampersand remains in the 24-image
        // acceptance corpus and is exercised after full pipeline integration.
        let identifiers = ["uni0061", "uni0065", "uni0073", "uni0052", "uni004F", "uni0053", "uni006E"]
        for identifier in identifiers {
            try assertPlansMatchOracle(identifier: identifier)
        }
    }

    func testAllBasicLatinStructuralPlansMatchPinnedOracle() throws {
        let root = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
        let identifiers = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent.hasPrefix("uni") }
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(identifiers.count, 62)
        for identifier in identifiers { try assertPlansMatchOracle(identifier: identifier) }
    }

    private func assertPlansMatchOracle(identifier: String) throws {
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
                threshold: .fixed(metadata.threshold),
                invert: metadata.invert,
                recoverLowResolution: false
            )
        )
        let scale = metadata.options.emHeight / Double(prepared.raster.height)
        let contours = SubpixelExtractor.glyphContours(
            raster: prepared.raster,
            threshold: prepared.threshold,
            invert: prepared.invert,
            minimumAreaPixels: max(100 / (scale * scale), 2)
        )
        let raster = RasterTarget(
            raster: prepared.raster,
            invert: prepared.invert,
            pixelsPerUnit: 1 / scale
        )
        let stageURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("structural-plan-") }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        XCTAssertEqual(stageURLs.count, contours.count, identifier)

        for stageURL in stageURLs {
            let expected = try decoder.decode(PlanStage.self, from: Data(contentsOf: stageURL))
            guard case .plan(let actual) = ContourPlanner.plan(
                contour: contours[expected.contourIndex],
                configuration: .capturedDefaults,
                raster: raster
            ) else {
                XCTFail("\(identifier) contour \(expected.contourIndex) did not produce a plan")
                continue
            }
            XCTAssertEqual(actual.smoothed.count, expected.smoothed.count, identifier)
            for (point, oracle) in zip(actual.smoothed, expected.smoothed) {
                XCTAssertEqual(point.x, oracle.x, accuracy: 1e-9, identifier)
                XCTAssertEqual(point.y, oracle.y, accuracy: 1e-9, identifier)
            }
            let actualDescription = actual.splits.map { "\($0.index):\($0.kind.oracleName)" }
            let expectedDescription = expected.splits.map { "\($0.index):\($0.kind)" }
            XCTAssertEqual(
                actualDescription,
                expectedDescription,
                "\(identifier) actual=\(actualDescription) expected=\(expectedDescription)"
            )
            XCTAssertEqual(
                actual.lineSections.map { [$0.start, $0.end] },
                expected.lineSections,
                identifier
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
