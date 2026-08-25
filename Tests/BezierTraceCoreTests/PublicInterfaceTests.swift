// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
import BezierTraceCore

final class PublicInterfaceTests: XCTestCase {
    func testDefaultTraceProducesStableVersionedNeutralResult() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        let request = TraceRequest(imageData: data)

        let first = try BezierTracer.trace(request)
        let second = try BezierTracer.trace(request)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.schemaVersion, 1)
        XCTAssertEqual(first.pathDataVersion, 2)
        XCTAssertEqual(first.metadataPolicy, "preserve")
        XCTAssertEqual(first.engine.name, "beztrace")
        XCTAssertEqual(first.engine.version, "0.1.0")
        XCTAssertEqual(
            first.engine.portSourceRevision,
            "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
        )
        XCTAssertEqual(
            first.source.sha256,
            "7287b7f907c4288ec5ee1cbebc223f604c74dfbe97be2eb1f1fb1163282b536c"
        )
        XCTAssertEqual(first.source.format, .png)
        XCTAssertEqual(first.source.width, 1024)
        XCTAssertEqual(first.source.height, 1024)
        XCTAssertFalse(first.source.usedAlphaMask)
        XCTAssertEqual(first.resolvedOptions.thresholdMethod, .automatic)
        XCTAssertEqual(first.resolvedOptions.targetHeight, 1088)
        XCTAssertNil(first.placement)
        XCTAssertTrue(first.timingsMs.isEmpty)
        XCTAssertEqual(first.outline.contours.count, 2)
        XCTAssertEqual(first.statistics.contourCount, 2)
        XCTAssertGreaterThan(first.statistics.nodeCount, 0)
        XCTAssertNotNil(first.bounds)
    }

    func testJSONRoundTripsAndSVGUsesTheSameOutline() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-o.png")
        let result = try BezierTracer.trace(TraceRequest(
            imageData: data,
            options: TraceOptions(threshold: .fixed(127))
        ))

        let firstJSON = try TraceSerializer.json(result)
        let secondJSON = try TraceSerializer.json(result)
        XCTAssertEqual(firstJSON, secondJSON)

        let decoded = try JSONDecoder().decode(TraceResult.self, from: firstJSON)
        XCTAssertEqual(decoded, result)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstJSON) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["pathDataVersion"] as? Int, 2)
        XCTAssertNotNil(object["paths"] as? [[String: Any]])
        XCTAssertNil(object["outline"])

        let svg = try TraceSerializer.svg(result)
        XCTAssertTrue(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(svg.contains("fill-rule=\"nonzero\""))
        XCTAssertTrue(svg.contains("<path d=\"\(TraceSerializer.svgPathData(for: decoded.outline))\""))
        XCTAssertFalse(svg.contains("/Users/"))
        XCTAssertFalse(svg.contains("glyph-upper-o.png"))
    }

    func testExplicitPlacementFitsInkAndResolvesMetrics() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        let placement = PlacementOptions(
            sourceBox: .ink,
            targetYMin: 0,
            targetYMax: 700,
            horizontalMode: .sidebearings(left: 50, right: 60),
            grid: 2
        )
        let result = try BezierTracer.trace(TraceRequest(
            imageData: data,
            placement: placement
        ))
        let report = try XCTUnwrap(result.placement)
        let bounds = try XCTUnwrap(result.bounds)

        XCTAssertEqual(report.finalBounds, bounds)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 700, accuracy: 2.001)
        XCTAssertEqual(report.leftSideBearing, 50, accuracy: 0.001)
        XCTAssertEqual(report.rightSideBearing, 60, accuracy: 0.001)
        XCTAssertEqual(report.advanceWidth, bounds.maxX + 60, accuracy: 0.001)
        XCTAssertEqual(report.imageWidth, 1024)
        XCTAssertEqual(report.imageHeight, 1024)
        XCTAssertGreaterThan(report.inkBoundsPixels.width, 0)
        XCTAssertFalse(report.outOfTarget)
    }

    func testInvalidOptionsAndPlacementFailBeforeTracing() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")

        XCTAssertThrowsError(try BezierTracer.trace(TraceRequest(
            imageData: data,
            options: TraceOptions(accuracy: .nan)
        ))) { error in
            XCTAssertEqual(error as? TraceError, .invalidOptions("accuracy must be finite and greater than zero"))
        }
        XCTAssertThrowsError(try BezierTracer.trace(TraceRequest(
            imageData: data,
            placement: PlacementOptions(
                sourceBox: .ink,
                targetYMin: 700,
                targetYMax: 0,
                horizontalMode: .centered(advance: 800)
            )
        ))) { error in
            XCTAssertEqual(error as? TraceError, .invalidPlacement("targetYMax must be greater than targetYMin"))
        }
    }

    func testAllCorpusResultsSerializeDeterministically() throws {
        struct Manifest: Decodable {
            struct Fixture: Decodable { let id: String; let path: String }
            let fixtures: [Fixture]
        }
        let root = repositoryRoot.appendingPathComponent("Tests/Fixtures", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(manifest.fixtures.count, 24)
        for fixture in manifest.fixtures {
            let data = try Data(contentsOf: root.appendingPathComponent(fixture.path))
            let first = try TraceSerializer.json(BezierTracer.trace(.init(imageData: data)))
            let second = try TraceSerializer.json(BezierTracer.trace(.init(imageData: data)))
            XCTAssertEqual(first, second, fixture.id)
        }
    }

    private func fixtureData(_ path: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(path))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
