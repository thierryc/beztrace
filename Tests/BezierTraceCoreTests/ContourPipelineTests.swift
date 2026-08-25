// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class ContourPipelineTests: XCTestCase {
    private struct FixtureManifest: Decodable {
        struct Fixture: Decodable { let id: String; let path: String }
        let fixtures: [Fixture]
    }

    private struct CorpusManifest: Decodable {
        struct Fixture: Decodable { let id: String; let contours: Int }
        let fixtures: [Fixture]
    }

    func testAllReviewedCorpusImagesProduceExpectedClosedTopology() throws {
        let fixturesRoot = repositoryRoot.appendingPathComponent("Tests/Fixtures", isDirectory: true)
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(
            FixtureManifest.self,
            from: Data(contentsOf: fixturesRoot.appendingPathComponent("manifest.json"))
        )
        let corpus = try decoder.decode(
            CorpusManifest.self,
            from: Data(contentsOf: fixturesRoot.appendingPathComponent("oracle/v1/corpus/corpus-manifest.json"))
        )
        let expectedCounts = Dictionary(uniqueKeysWithValues: corpus.fixtures.map { ($0.id, $0.contours) })
        XCTAssertEqual(manifest.fixtures.count, 24)

        for fixture in manifest.fixtures {
            let result = try ContourPipeline.extract(
                data: Data(contentsOf: fixturesRoot.appendingPathComponent(fixture.path)),
                options: RasterPreparationOptions()
            )
            XCTAssertEqual(result.contours.count, expectedCounts[fixture.id], fixture.id)
            XCTAssertTrue(result.contours.allSatisfy(\.isFinite), fixture.id)
            XCTAssertTrue(result.contours.allSatisfy { $0.points.count >= 8 }, fixture.id)
            XCTAssertTrue(result.contours.allSatisfy { $0.bounds != nil }, fixture.id)
        }
    }

    func testInvalidFoundationOptionsFailClosed() throws {
        let fixture = repositoryRoot.appendingPathComponent(
            "Tests/Fixtures/corpus/deterministic/glyphs/glyph-upper-a.png"
        )
        let data = try Data(contentsOf: fixture)
        XCTAssertThrowsError(try ContourPipeline.extract(
            data: data,
            options: .init(targetHeight: .nan)
        )) { error in
            XCTAssertEqual(error as? CoreError, .invalidOptions)
        }
        XCTAssertThrowsError(try ContourPipeline.extract(
            data: data,
            options: .init(minimumContourArea: -1)
        )) { error in
            XCTAssertEqual(error as? CoreError, .invalidOptions)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
