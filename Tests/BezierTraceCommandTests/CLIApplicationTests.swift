// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import BezierTraceCommand

final class CLIApplicationTests: XCTestCase {
    func testVersionAndArgumentErrorsHaveStableStreamsAndCodes() throws {
        let version = CLIApplication.run(arguments: ["--version"])
        XCTAssertEqual(version.exitCode, 0)
        XCTAssertEqual(String(data: version.standardOutput, encoding: .utf8), "beztrace 0.1.0\n")
        XCTAssertTrue(version.standardError.isEmpty)

        let missing = CLIApplication.run(arguments: ["trace"])
        XCTAssertEqual(missing.exitCode, 2)
        XCTAssertTrue(missing.standardOutput.isEmpty)
        XCTAssertEqual(
            String(data: missing.standardError, encoding: .utf8),
            "beztrace: trace requires exactly one input\n"
        )

        let jsonError = CLIApplication.run(arguments: ["trace", "--json-errors"])
        XCTAssertEqual(jsonError.exitCode, 2)
        XCTAssertTrue(jsonError.standardOutput.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: jsonError.standardError) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["exitCode"] as? Int, 2)
    }

    func testTracePathAndStandardInputProduceMachineReadableOutput() throws {
        let input = fixture("corpus/deterministic/glyphs/glyph-upper-a.png")
        let json = CLIApplication.run(arguments: [
            "trace", input.path, "--format", "json",
        ])
        XCTAssertEqual(json.exitCode, 0)
        XCTAssertTrue(json.standardError.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: json.standardOutput) as? [String: Any]
        )
        XCTAssertEqual(object["pathDataVersion"] as? Int, 2)

        let svg = CLIApplication.run(
            arguments: ["trace", "-", "--format", "svg"],
            standardInput: try Data(contentsOf: input)
        )
        XCTAssertEqual(svg.exitCode, 0)
        XCTAssertTrue(svg.standardError.isEmpty)
        XCTAssertTrue(String(decoding: svg.standardOutput, as: UTF8.self).hasPrefix("<svg "))
    }

    func testTraceOutputPlacementAndInspectContracts() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("beztrace-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("placed.json")
        let input = fixture("corpus/deterministic/glyphs/glyph-upper-a.png")
        let trace = CLIApplication.run(arguments: [
            "trace", input.path, "--format", "json", "--output", output.path,
            "--threshold", "127", "--accuracy", "2", "--smoothing", "1",
            "--corner-threshold", "12", "--min-contour-area", "100",
            "--grid", "2", "--structure-grid", "0", "--refine-raster",
            "--target-y-min", "0", "--target-y-max", "700",
            "--source-box", "ink", "--lsb", "50", "--rsb", "60",
        ])
        XCTAssertEqual(trace.exitCode, 0, String(decoding: trace.standardError, as: UTF8.self))
        XCTAssertTrue(trace.standardOutput.isEmpty)
        XCTAssertTrue(trace.standardError.isEmpty)
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
        XCTAssertNotNil(result?["placement"])

        let inspect = CLIApplication.run(arguments: ["inspect", input.path, "--format", "json"])
        XCTAssertEqual(inspect.exitCode, 0)
        XCTAssertTrue(inspect.standardError.isEmpty)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: inspect.standardOutput))
    }

    func testBatchPreservesInputOrderAndWritesOnlyRequestedDirectory() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("beztrace-batch-tests-\(UUID().uuidString)", isDirectory: true)
        let output = temporary.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = fixture("corpus/deterministic/symbols/symbol-check.png")
        let second = fixture("corpus/deterministic/glyphs/glyph-upper-a.png")

        let run = CLIApplication.run(arguments: [
            "batch", first.path, second.path,
            "--format", "json", "--output-dir", output.path,
        ])
        XCTAssertEqual(run.exitCode, 0, String(decoding: run.standardError, as: UTF8.self))
        XCTAssertTrue(run.standardOutput.isEmpty)
        XCTAssertTrue(run.standardError.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        XCTAssertEqual(names, ["glyph-upper-a.json", "symbol-check.json"])
        for name in names {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(
                with: Data(contentsOf: output.appendingPathComponent(name))
            ))
        }
    }

    func testInputAndNoContourFailuresUseDocumentedExitCodes() throws {
        let missing = CLIApplication.run(arguments: [
            "trace", "/definitely/missing/beztrace.png", "--format", "json",
        ])
        XCTAssertEqual(missing.exitCode, 3)
        XCTAssertTrue(missing.standardOutput.isEmpty)

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("beztrace-empty-\(UUID().uuidString).png")
        try opaqueWhitePNG().write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let empty = CLIApplication.run(arguments: [
            "trace", temporary.path, "--format", "json",
        ])
        XCTAssertEqual(empty.exitCode, 4)
        XCTAssertTrue(empty.standardOutput.isEmpty)
    }

    func testInvalidOutputPathReturnsSerializationExitCode() {
        let input = fixture("corpus/deterministic/glyphs/glyph-upper-a.png")
        let result = CLIApplication.run(arguments: [
            "trace", input.path, "--format", "json",
            "--output", "/definitely/missing/beztrace/output.json",
        ])
        XCTAssertEqual(result.exitCode, 6)
        XCTAssertTrue(result.standardOutput.isEmpty)
    }

    func testInvalidOptionCombinationsFailBeforeInputAccess() {
        let cases: [([String], String)] = [
            (["trace", "missing.png"], "--format is required"),
            (["trace", "missing.png", "--format", "json", "--threshold", "256"],
             "threshold must be auto or 0...255"),
            (["trace", "missing.png", "--format", "json", "--target-y-min", "0"],
             "placement requires --target-y-min and --target-y-max"),
            (["trace", "missing.png", "--format", "json", "--target-y-min", "0",
              "--target-y-max", "700", "--lsb", "40", "--rsb", "40",
              "--center-in-advance", "800"],
             "select exactly one horizontal placement mode"),
            (["batch", "-", "--format", "json", "--output-dir", "/tmp/beztrace-invalid"],
             "batch input must be a local path"),
            (["inspect", "missing.png", "--format", "svg"], "inspect format must be json"),
        ]
        for (arguments, message) in cases {
            let result = CLIApplication.run(arguments: arguments)
            XCTAssertEqual(result.exitCode, 2, arguments.joined(separator: " "))
            XCTAssertTrue(result.standardOutput.isEmpty)
            XCTAssertEqual(String(decoding: result.standardError, as: UTF8.self), "beztrace: \(message)\n")
        }
    }

    func testMalformedBytesReturnInputExitCodeAndJSONError() throws {
        let result = CLIApplication.run(
            arguments: ["trace", "-", "--format", "json", "--json-errors"],
            standardInput: Data("not an image".utf8)
        )
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.standardOutput.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: result.standardError) as? [String: Any]
        )
        XCTAssertEqual(object["exitCode"] as? Int, 3)
        let detail = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertEqual(detail["type"] as? String, "input")
    }

    private func fixture(_ path: String) -> URL {
        repositoryRoot.appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(path)
    }

    private func opaqueWhitePNG() throws -> Data {
        let width = 32
        let height = 32
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bytes = Array(repeating: UInt8(255), count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
