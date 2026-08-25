// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class CubicFittingTests: XCTestCase {
    private struct PreparedMetadata: Decodable {
        struct Options: Decodable { let emHeight: Double }
        let threshold: UInt8
        let invert: Bool
        let options: Options
    }

    private struct InitialFitStage: Decodable {
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

    private struct StructuralPlanStage: Decodable {
        struct Sample: Decodable { let x: Double; let y: Double }
        struct Split: Decodable { let index: Int; let kind: String }
        let smoothed: [Sample]
        let splits: [Split]
        let lineSections: [[Int]]
    }

    func testConstrainedCubicHonorsEndpointTangents() {
        let samples = (0...32).map { index -> Point2D in
            let angle = Double(index) / 32 * .pi / 2
            return Point2D(x: 100 * cos(angle), y: 100 * sin(angle))
        }
        let result = ContourFitter.constrainedCubicFit(
            samples: samples,
            startTangent: Vector2D(dx: 0, dy: 1),
            endTangent: Vector2D(dx: 1, dy: 0)
        )

        XCTAssertEqual(result.curve.start, samples.first)
        XCTAssertEqual(result.curve.end, samples.last)
        XCTAssertEqual(result.curve.control1.x, result.curve.start.x, accuracy: 1e-12)
        XCTAssertEqual(result.curve.control2.y, result.curve.end.y, accuracy: 1e-12)
        XCTAssertLessThan(result.maximumError, 0.07)
    }

    func testOpenFallbackIsDeterministicAndBounded() {
        let samples = (0...400).map { index -> Point2D in
            let t = Double(index) / 400
            return Point2D(
                x: 400 * t,
                y: 35 * sin(t * .pi * 8) + 10 * sin(t * .pi * 19)
            )
        }
        let first = ContourFitter.fitOpenSamples(samples, accuracy: 0.25)
        let second = ContourFitter.fitOpenSamples(samples, accuracy: 0.25)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertLessThanOrEqual(first.count, 24)
    }

    func testFocusedInitialFitsMatchPinnedOracle() throws {
        let identifiers = ["uni0061", "uni0065", "uni0073", "uni0052", "uni004F", "uni0053", "uni006E"]
        for identifier in identifiers {
            try assertInitialFitsMatchOracle(identifier: identifier)
        }
    }

    func testAllBasicLatinInitialFitsMatchPinnedOracle() throws {
        let root = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
        let identifiers = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent.hasPrefix("uni") }
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(identifiers.count, 62)
        for identifier in identifiers { try assertInitialFitsMatchOracle(identifier: identifier) }
    }

    func testInitialFinishMergesOnlySmoothCollinearLines() {
        let first = lineCubic(from: Point2D(x: 0, y: 0), to: Point2D(x: 5, y: 0.1))
        let second = lineCubic(from: first.end, to: Point2D(x: 10, y: 0))
        let third = lineCubic(from: second.end, to: first.start)
        let input = FittedContour(
            segments: [first, second, third],
            isLine: [true, true, true],
            jointKinds: [.corner, .tangent, .corner]
        )

        let merged = FittingFinish.mergeCollinearLines(input)
        XCTAssertEqual(merged.segments.count, 2)
        XCTAssertEqual(merged.segments[0], lineCubic(from: first.start, to: second.end))
        XCTAssertEqual(merged.jointKinds, [.corner, .corner])
    }

    func testSmoothJoinPreservesHandleLengthsAndAlignsDirections() {
        let first = CubicBezier(
            start: Point2D(x: 0, y: 0),
            control1: Point2D(x: 3, y: 0),
            control2: Point2D(x: 7, y: -1),
            end: Point2D(x: 10, y: 0)
        )
        let second = CubicBezier(
            start: first.end,
            control1: Point2D(x: 13, y: 1),
            control2: Point2D(x: 17, y: 0),
            end: Point2D(x: 20, y: 0)
        )
        let closing = lineCubic(from: second.end, to: first.start)
        let input = FittedContour(
            segments: [first, second, closing],
            isLine: [false, false, true],
            jointKinds: [.corner, .fitterJoint, .corner]
        )

        let smoothed = FittingFinish.smoothJoins(input)
        let incoming = first.end - smoothed.segments[0].control2
        let outgoing = smoothed.segments[1].control1 - second.start
        XCTAssertEqual(incoming.cross(outgoing), 0, accuracy: 1e-12)
        XCTAssertEqual(incoming.magnitude, (first.end - first.control2).magnitude, accuracy: 1e-12)
        XCTAssertEqual(outgoing.magnitude, (second.control1 - second.start).magnitude, accuracy: 1e-12)
    }

    private func assertInitialFitsMatchOracle(identifier: String) throws {
        let directory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/oracle/v1/basic-latin", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(
            PreparedMetadata.self,
            from: Data(contentsOf: directory.appendingPathComponent("prepared-raster.json"))
        )
        let scale = metadata.options.emHeight / Double(try pngHeight(
            at: directory.appendingPathComponent("prepared-raster.png")
        ))
        let accuracy = min(max(TraceConfiguration.capturedDefaults.fitAccuracy / scale, 0.5), 3)
        let stageURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("initial-fit-") }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        for stageURL in stageURLs {
            let expected = try decoder.decode(InitialFitStage.self, from: Data(contentsOf: stageURL))
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
                    guard $0.count == 2 else { throw TestDecodeError.invalidLineSection }
                    return LineSection(start: $0[0], end: $0[1])
                }
            )
            let actual = ContourFitter.fitInitial(plan: plan, accuracy: accuracy).pathElements
            XCTAssertEqual(actual.count, expected.path.elements.count, identifier)
            guard actual.count == expected.path.elements.count else { continue }
            let tolerance = 0.25 / scale
            for (element, oracle) in zip(actual, expected.path.elements) {
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
                    XCTFail("\(identifier) path element topology differs: \(element) vs \(oracle.type)")
                }
            }
        }
    }

    private enum TestDecodeError: Error { case invalidSplitKind(String); case invalidLineSection; case invalidPNG }

    private func splitKind(named name: String) throws -> SplitKind {
        switch name {
        case "Corner": .corner
        case "Tangent": .tangent
        case "ExtremumX": .extremumX
        case "ExtremumY": .extremumY
        case "Inflection": .inflection
        case "FitterJoint": .fitterJoint
        default: throw TestDecodeError.invalidSplitKind(name)
        }
    }

    private func pngHeight(at url: URL) throws -> Int {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 24, data.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw TestDecodeError.invalidPNG
        }
        return data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
