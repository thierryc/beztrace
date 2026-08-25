// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class CleanupValidationTests: XCTestCase {
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

    private struct CleanedStage: Decodable {
        struct CapturedContour: Decodable { let index: Int; let path: Path }
        struct Path: Decodable { let elements: [Element] }
        struct Element: Decodable {
            let type: String
            let x: Double?
            let y: Double?
            let points: [[Double]]?
        }
        let contours: [CapturedContour]
    }

    private struct ValidatedStage: Decodable {
        struct CapturedOutline: Decodable { let contours: [CapturedContour] }
        struct CapturedContour: Decodable { let points: [Point] }
        struct Point: Decodable {
            let x: Double
            let y: Double
            let type: String?
            let smooth: Bool?
        }
        let outline: CapturedOutline
    }

    func testFocusedCleanedAndValidatedOutlinesMatchPinnedOracle() throws {
        let identifiers = ["uni0061", "uni0065", "uni0073", "uni0052", "uni004F", "uni0053", "uni006E"]
        for identifier in identifiers { try assertCleanupMatchesOracle(identifier: identifier) }
    }

    func testLowercaseYCleanedAndValidatedOutlineMatchesPinnedOracle() throws {
        try assertCleanupMatchesOracle(identifier: "uni0079")
    }

    func testAllBasicLatinCleanedAndValidatedOutlinesMatchPinnedOracle() throws {
        let identifiers = try basicLatinIdentifiers()
        XCTAssertEqual(identifiers.count, 62)
        for identifier in identifiers { try assertCleanupMatchesOracle(identifier: identifier) }
    }

    func testMaintenanceExportWritesBasicLatinEvaluationUFO() throws {
        guard let work = ProcessInfo.processInfo.environment["BEZTRACE_EXTERNAL_WORK"] else {
            throw XCTSkip("set BEZTRACE_EXTERNAL_WORK for explicit maintenance export")
        }
        var outlines: [(name: String, outline: ValidatedOutline)] = []
        for identifier in try basicLatinIdentifiers() {
            let scalar = try XCTUnwrap(UInt32(identifier.dropFirst(3), radix: 16))
            let character = try XCTUnwrap(UnicodeScalar(scalar)).description
            let name: String
            switch character {
            case "0": name = "zero"
            case "1": name = "one"
            case "2": name = "two"
            case "3": name = "three"
            case "4": name = "four"
            case "5": name = "five"
            case "6": name = "six"
            case "7": name = "seven"
            case "8": name = "eight"
            case "9": name = "nine"
            default: name = character
            }
            outlines.append((name, try assertCleanupMatchesOracle(identifier: identifier)))
        }
        let output = URL(fileURLWithPath: work, isDirectory: true)
            .appendingPathComponent("tmp/swift-basic-latin.ufo", isDirectory: true)
        try TestOutlineExporter.writeUFO(outlines, to: output)
        XCTAssertEqual(outlines.count, 62)
    }

    func testValidationRejectsNonFiniteAndSelfIntersectingGeometry() {
        let nonFinite = BezierPathContour(segments: [
            PathSegment(cubic: lineCubic(
                from: Point2D(x: .nan, y: 0),
                to: Point2D(x: 1, y: 1)
            ), isLine: true),
        ])
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [nonFinite])) {
            XCTAssertEqual($0 as? CoreError, .nonFiniteGeometry)
        }

        let points = [
            Point2D(x: 0, y: 0), Point2D(x: 10, y: 10),
            Point2D(x: 0, y: 10), Point2D(x: 10, y: 0),
        ]
        let crossing = BezierPathContour(segments: points.indices.map {
            PathSegment(
                cubic: lineCubic(from: points[$0], to: points[($0 + 1) % points.count]),
                isLine: true
            )
        })
        XCTAssertThrowsError(try OutlineValidator.validate(paths: [crossing])) {
            XCTAssertEqual($0 as? CoreError, .selfIntersection(contour: 0))
        }
    }

    func testDeterministicStartNormalizationChoosesBottomLeftOnCurve() throws {
        let points = [
            Point2D(x: 10, y: 10), Point2D(x: 0, y: 0),
            Point2D(x: 10, y: 0), Point2D(x: 20, y: 10),
        ]
        let path = BezierPathContour(segments: points.indices.map {
            PathSegment(
                cubic: lineCubic(from: points[$0], to: points[($0 + 1) % points.count]),
                isLine: true
            )
        })
        let outline = try OutlineValidator.validate(paths: [path])
        XCTAssertEqual(outline.contours[0].points[0].position, Point2D(x: 0, y: 0))
    }

    func testStrongInflectionSplitsWithoutChangingCurve() {
        let curve = CubicBezier(
            start: Point2D(x: 300, y: 250),
            control1: Point2D(x: 300, y: 150),
            control2: Point2D(x: 0, y: 350),
            end: Point2D(x: 0, y: 0)
        )
        let path = BezierPathContour(segments: [PathSegment(cubic: curve, isLine: false)])
        let split = CleanupInflection.splitInflections(path, grid: 0)
        XCTAssertEqual(split.segments.count, 2)
        guard split.segments.count == 2,
              let splitParameter = CleanupInflection.splitParameter(curve)
        else { return }
        for sample in 0...20 {
            let parameter = Double(sample) / 20
            let rebuilt: Point2D
            if parameter <= splitParameter {
                rebuilt = split.segments[0].cubic.point(at: parameter / splitParameter)
            } else {
                rebuilt = split.segments[1].cubic.point(
                    at: (parameter - splitParameter) / (1 - splitParameter)
                )
            }
            XCTAssertEqual(rebuilt.x, curve.point(at: parameter).x, accuracy: 1e-8)
            XCTAssertEqual(rebuilt.y, curve.point(at: parameter).y, accuracy: 1e-8)
        }
    }

    func testOptionalChamferAddsOneBevelPerSquareCorner() {
        let points = [
            Point2D(x: 0, y: 0), Point2D(x: 100, y: 0),
            Point2D(x: 100, y: 100), Point2D(x: 0, y: 100),
        ]
        let square = BezierPathContour(segments: points.indices.map {
            PathSegment(
                cubic: lineCubic(from: points[$0], to: points[($0 + 1) % points.count]),
                isLine: true
            )
        })
        let result = CleanupChamfer.chamfer(square, size: 10, minimumEdge: 5)
        XCTAssertEqual(result.segments.count, 8)
        XCTAssertTrue(result.segments.allSatisfy(\.isLine))
    }

    func testGridSnapsOnlyOnCurvePointsAndHandleCapControlsReach() {
        let curve = CubicBezier(
            start: Point2D(x: 0.9, y: 1.1),
            control1: Point2D(x: 180.4, y: 1.3),
            control2: Point2D(x: -79.6, y: 100.7),
            end: Point2D(x: 99.2, y: 100.9)
        )
        let path = BezierPathContour(segments: [
            PathSegment(cubic: curve, isLine: false),
            PathSegment(cubic: lineCubic(from: curve.end, to: curve.start), isLine: true),
        ])
        let snapped = CleanupSnap.toGrid(path, fine: 2, structure: 0)
        XCTAssertEqual(snapped.segments[0].cubic.start, Point2D(x: 0, y: 2))
        XCTAssertEqual(snapped.segments[0].cubic.control1, curve.control1)
        let capped = CleanupEven.capHandles(snapped)
        let value = capped.segments[0].cubic
        let chord = value.end - value.start
        let direction = chord / chord.magnitude
        let reach = (value.control1 - value.start).dot(direction)
            - (value.control2 - value.end).dot(direction)
        XCTAssertLessThanOrEqual(reach, chord.magnitude * 0.9 + 1e-9)
    }

    @discardableResult
    private func assertCleanupMatchesOracle(identifier: String) throws -> ValidatedOutline {
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
        let structuralURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("structural-plan-") }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        var fittedContours: [FittedContour] = []
        for url in structuralURLs {
            let stage = try decoder.decode(StructuralPlanStage.self, from: Data(contentsOf: url))
            let plan = ContourPlan(
                smoothed: stage.smoothed.map { Point2D(x: $0.x, y: $0.y) },
                splits: try stage.splits.map {
                    StructuralSplit(index: $0.index, kind: try splitKind(named: $0.kind))
                },
                lineSections: try stage.lineSections.map {
                    guard $0.count == 2 else { throw DecodeFailure.invalidLineSection }
                    return LineSection(start: $0[0], end: $0[1])
                }
            )
            let initial = ContourFitter.fitInitial(plan: plan, accuracy: accuracy)
            var refined = ContourRefiner.refine(initial, raster: raster)
            refined = FittingFinish.harmonize(refined)
            refined = FittingFinish.capHandleReach(refined)
            fittedContours.append(refined.scaled(by: scale))
        }
        let cleaned = CleanupPipeline.process(
            fittedContours.map(BezierPathContour.init),
            configuration: .capturedDefaults
        )
        let expectedCleaned = try decoder.decode(
            CleanedStage.self,
            from: Data(contentsOf: directory.appendingPathComponent("cleaned.json"))
        )
        XCTAssertEqual(cleaned.count, expectedCleaned.contours.count, identifier)
        for expected in expectedCleaned.contours {
            try assertPath(
                cleaned[expected.index].pathElements,
                matches: expected.path.elements,
                tolerance: 1,
                identifier: identifier
            )
        }

        let validated = try OutlineValidator.validate(paths: cleaned)
        let expectedValidated = try decoder.decode(
            ValidatedStage.self,
            from: Data(contentsOf: directory.appendingPathComponent("validated.json"))
        )
        XCTAssertEqual(validated.contours.count, expectedValidated.outline.contours.count, identifier)
        for (contour, oracle) in zip(validated.contours, expectedValidated.outline.contours) {
            XCTAssertEqual(contour.points.count, oracle.points.count, identifier)
            guard contour.points.count == oracle.points.count else { continue }
            for (point, expectedPoint) in zip(contour.points, oracle.points) {
                XCTAssertEqual(point.position.x, expectedPoint.x, accuracy: 1e-9, identifier)
                XCTAssertEqual(point.position.y, expectedPoint.y, accuracy: 1e-9, identifier)
                XCTAssertEqual(point.kind.oracleName, expectedPoint.type, identifier)
                XCTAssertEqual(point.smooth, expectedPoint.smooth ?? false, identifier)
            }
        }
        return validated
    }

    private func basicLatinIdentifiers() throws -> [String] {
        let root = repositoryRoot.appendingPathComponent(
            "Tests/Fixtures/oracle/v1/basic-latin",
            isDirectory: true
        )
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && $0.lastPathComponent.hasPrefix("uni")
        }.map(\.lastPathComponent).sorted()
    }

    private func assertPath(
        _ actual: [InternalPathElement],
        matches expected: [CleanedStage.Element],
        tolerance: Double,
        identifier: String
    ) throws {
        XCTAssertEqual(
            actual.count,
            expected.count,
            "\(identifier) actual=\(actual) expected=\(expected.map(\.type))"
        )
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
                XCTFail("\(identifier) cleaned path topology differs: \(element) vs \(oracle.type)")
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
