// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class SubpixelDifferentialTests: XCTestCase {
    private struct PreparedMetadata: Decodable {
        struct Options: Decodable { let emHeight: Double }
        let width: Int
        let height: Int
        let threshold: UInt8
        let invert: Bool
        let options: Options
    }

    private struct ContourStage: Decodable {
        struct OracleContour: Decodable {
            struct OraclePoint: Decodable { let x: Double; let y: Double }
            let points: [OraclePoint]
        }
        let contours: [OracleContour]
    }

    func testAllBasicLatinSubpixelContoursMatchPinnedOracle() throws {
        let root = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
        let fixtureDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent.hasPrefix("uni") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fixtureDirectories.count, 62)

        var maximumDeviation = 0.0
        for fixture in fixtureDirectories {
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(
                PreparedMetadata.self,
                from: Data(contentsOf: fixture.appendingPathComponent("prepared-raster.json"))
            )
            let oracle = try decoder.decode(
                ContourStage.self,
                from: Data(contentsOf: fixture.appendingPathComponent("subpixel-contours.json"))
            )
            let prepared = try RasterPreparer.prepare(
                data: Data(contentsOf: fixture.appendingPathComponent("prepared-raster.png")),
                options: .init(
                    threshold: .fixed(metadata.threshold),
                    invert: metadata.invert,
                    recoverLowResolution: false
                )
            )
            XCTAssertEqual(prepared.raster.width, metadata.width, fixture.lastPathComponent)
            XCTAssertEqual(prepared.raster.height, metadata.height, fixture.lastPathComponent)
            let scale = metadata.options.emHeight / Double(metadata.height)
            let minimumArea = max(100 / (scale * scale), 2)
            let actual = SubpixelExtractor.glyphContours(
                raster: prepared.raster,
                threshold: prepared.threshold,
                invert: prepared.invert,
                minimumAreaPixels: minimumArea
            )

            XCTAssertEqual(actual.count, oracle.contours.count, fixture.lastPathComponent)
            guard actual.count == oracle.contours.count else { continue }
            for contourIndex in actual.indices {
                let expectedPoints = oracle.contours[contourIndex].points
                XCTAssertEqual(
                    actual[contourIndex].points.count,
                    expectedPoints.count,
                    "\(fixture.lastPathComponent) contour \(contourIndex)"
                )
                guard actual[contourIndex].points.count == expectedPoints.count else { continue }
                for pointIndex in actual[contourIndex].points.indices {
                    let point = actual[contourIndex].points[pointIndex]
                    let expected = expectedPoints[pointIndex]
                    let deviation = hypot(point.x - expected.x, point.y - expected.y)
                    maximumDeviation = max(maximumDeviation, deviation)
                    XCTAssertLessThanOrEqual(
                        deviation,
                        1e-9,
                        "\(fixture.lastPathComponent) contour \(contourIndex) point \(pointIndex)"
                    )
                }
            }
        }
        XCTAssertLessThanOrEqual(maximumDeviation, 0.25)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
