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

    func testJSONRoundTripsAndSVGTransformModesUseTheSameOutline() throws {
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

        let baked = try TraceSerializer.svg(result)
        let explicitBake = try TraceSerializer.svg(result, transformMode: .bake)
        XCTAssertEqual(baked, explicitBake)
        XCTAssertTrue(baked.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(baked.contains("fill-rule=\"nonzero\""))
        XCTAssertFalse(baked.contains("<g"))
        XCTAssertFalse(baked.contains("transform="))

        let preserved = try TraceSerializer.svg(result, transformMode: .preserve)
        XCTAssertTrue(preserved.contains("<g transform=\"translate(0 "))
        XCTAssertTrue(preserved.contains(" scale(1 -1)\">"))
        XCTAssertTrue(preserved.contains(
            "<path d=\"\(TraceSerializer.svgPathData(for: decoded.outline))\""
        ))
        XCTAssertNotEqual(baked, preserved)

        for svg in [baked, preserved] {
            XCTAssertFalse(svg.contains("/Users/"))
            XCTAssertFalse(svg.contains("glyph-upper-o.png"))
        }
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
        XCTAssertFalse(manifest.fixtures.isEmpty)
        XCTAssertEqual(Set(manifest.fixtures.map(\.id)).count, manifest.fixtures.count)
        for fixture in manifest.fixtures {
            let data = try Data(contentsOf: root.appendingPathComponent(fixture.path))
            let firstResult = try BezierTracer.trace(.init(imageData: data))
            let secondResult = try BezierTracer.trace(.init(imageData: data))
            XCTAssertEqual(firstResult, secondResult, fixture.id)
            XCTAssertFalse(firstResult.outline.contours.isEmpty, fixture.id)
            XCTAssertTrue(firstResult.outline.contours.allSatisfy(\.closed), fixture.id)
            XCTAssertTrue(
                firstResult.outline.contours.flatMap(\.nodes).allSatisfy {
                    $0.x.isFinite && $0.y.isFinite
                },
                fixture.id
            )

            let firstJSON = try TraceSerializer.json(firstResult)
            let secondJSON = try TraceSerializer.json(secondResult)
            XCTAssertEqual(firstJSON, secondJSON, fixture.id)

            let firstBake = try TraceSerializer.svg(firstResult, transformMode: .bake)
            let secondBake = try TraceSerializer.svg(secondResult, transformMode: .bake)
            let firstPreserve = try TraceSerializer.svg(firstResult, transformMode: .preserve)
            let secondPreserve = try TraceSerializer.svg(secondResult, transformMode: .preserve)
            XCTAssertEqual(firstBake, secondBake, fixture.id)
            XCTAssertEqual(firstPreserve, secondPreserve, fixture.id)
            XCTAssertFalse(firstBake.contains("transform="), fixture.id)
            XCTAssertTrue(firstPreserve.contains("transform="), fixture.id)
            XCTAssertEqual(svgCommandCounts(firstBake), svgCommandCounts(firstPreserve), fixture.id)
        }
    }

    func testVersionedJSONSchemaDescribesTheSerializedContract() throws {
        let schemaURL = repositoryRoot.appendingPathComponent("Schemas/trace-result-v1.schema.json")
        let schema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any]
        )
        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://beztrace.dev/schema/trace-result-v1.json")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertEqual(Set(required), [
            "schemaVersion", "engine", "source", "resolvedOptions", "pathDataVersion",
            "metadataPolicy", "paths", "bounds", "placement", "statistics", "timingsMs", "warnings",
        ])

        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        let result = try TraceSerializer.json(BezierTracer.trace(.init(imageData: data)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(required))
    }

    func testPublicErrorsPreserveInputAndResourceFailures() {
        XCTAssertThrowsError(try BezierTracer.trace(.init(imageData: Data()))) { error in
            XCTAssertEqual(error as? TraceError, .emptyInput)
        }
        XCTAssertThrowsError(try BezierTracer.trace(.init(imageData: Data("not an image".utf8)))) { error in
            XCTAssertEqual(error as? TraceError, .malformedImage)
        }
        let oversized = Data(repeating: 0, count: 16 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try BezierTracer.trace(.init(imageData: oversized))) { error in
            XCTAssertEqual(
                error as? TraceError,
                .encodedInputTooLarge(actual: oversized.count, limit: 16 * 1024 * 1024)
            )
        }
    }

    func testOtherHorizontalPlacementModesResolveDeterministically() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        let fixed = try BezierTracer.trace(.init(
            imageData: data,
            placement: PlacementOptions(
                targetYMin: 0,
                targetYMax: 700,
                horizontalMode: .advance(width: 800, left: 50)
            )
        ))
        XCTAssertEqual(fixed.placement?.advanceWidth, 800)
        XCTAssertEqual(fixed.placement?.leftSideBearing, 50)

        let centered = try BezierTracer.trace(.init(
            imageData: data,
            placement: PlacementOptions(
                targetYMin: 0,
                targetYMax: 700,
                horizontalMode: .centered(advance: 900)
            )
        ))
        let report = try XCTUnwrap(centered.placement)
        XCTAssertEqual(report.advanceWidth, 900)
        XCTAssertEqual(report.leftSideBearing, report.rightSideBearing, accuracy: 2.001)
    }

    func testSidebearingsCannotResolveANonpositiveAdvance() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        XCTAssertThrowsError(try BezierTracer.trace(.init(
            imageData: data,
            placement: PlacementOptions(
                targetYMin: 0,
                targetYMax: 700,
                horizontalMode: .sidebearings(left: -2_000, right: -2_000)
            )
        ))) { error in
            XCTAssertEqual(
                error as? TraceError,
                .invalidPlacement("resolved advance must be positive and finite")
            )
        }
    }

    func testSummaryDiagnosticsAreExplicitlyOptIn() throws {
        let data = try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png")
        let result = try BezierTracer.trace(.init(
            imageData: data,
            options: TraceOptions(diagnostics: .summary)
        ))
        XCTAssertEqual(result.timingsMs.keys.sorted(), ["total"])
        XCTAssertGreaterThan(result.timingsMs["total"] ?? 0, 0)
    }

    private func fixtureData(_ path: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(path))
    }

    private func svgCommandCounts(_ svg: String) -> [Character: Int] {
        Dictionary(uniqueKeysWithValues: ["M", "L", "C", "Z"].map { command in
            (command, svg.reduce(into: 0) { count, character in
                if character == command { count += 1 }
            })
        })
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
