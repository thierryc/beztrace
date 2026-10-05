// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest

final class CLIProcessTests: XCTestCase {
    func testBuiltExecutableVersionAndFailureStreams() throws {
        let version = try launch(["--version"])
        XCTAssertEqual(version.status, 0)
        XCTAssertEqual(String(decoding: version.output, as: UTF8.self), "beztrace 0.1.1\n")
        XCTAssertTrue(version.error.isEmpty)

        let failure = try launch(["trace"])
        XCTAssertEqual(failure.status, 2)
        XCTAssertTrue(failure.output.isEmpty)
        XCTAssertEqual(
            String(decoding: failure.error, as: UTF8.self),
            "beztrace: trace requires exactly one input\n"
        )
    }

    func testBuiltExecutableIsByteStableAcrossProcesses() throws {
        let input = repositoryRoot.appendingPathComponent(
            "Tests/Fixtures/corpus/deterministic/glyphs/glyph-upper-a.png"
        )
        let first = try launch(["trace", input.path, "--format", "json"])
        let second = try launch(["trace", input.path, "--format", "json"])
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(second.status, 0)
        XCTAssertTrue(first.error.isEmpty)
        XCTAssertTrue(second.error.isEmpty)
        XCTAssertEqual(first.output, second.output)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: first.output))
    }

    func testBuiltExecutableReadsRawImageFromStandardInput() throws {
        let input = repositoryRoot.appendingPathComponent(
            "Tests/Fixtures/corpus/deterministic/glyphs/glyph-upper-a.png"
        )
        let result = try launch(
            ["trace", "-", "--format", "svg"],
            input: Data(contentsOf: input)
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.error.isEmpty)
        let defaultSVG = String(decoding: result.output, as: UTF8.self)
        XCTAssertTrue(defaultSVG.hasPrefix("<svg "))
        XCTAssertFalse(defaultSVG.contains("transform="))

        let explicitBake = try launch(
            ["trace", "-", "--format", "svg", "--svg-transform", "bake"],
            input: Data(contentsOf: input)
        )
        XCTAssertEqual(explicitBake.status, 0)
        XCTAssertEqual(explicitBake.output, result.output)

        let preserve = try launch(
            ["trace", "-", "--format", "svg", "--svg-transform", "preserve"],
            input: Data(contentsOf: input)
        )
        XCTAssertEqual(preserve.status, 0)
        XCTAssertTrue(String(decoding: preserve.output, as: UTF8.self).contains("transform="))

        let invalid = try launch([
            "trace", input.path, "--format", "svg", "--svg-transform", "invalid",
        ])
        XCTAssertEqual(invalid.status, 2)
        XCTAssertEqual(
            String(decoding: invalid.error, as: UTF8.self),
            "beztrace: svg transform must be bake or preserve\n"
        )
    }

    private func launch(
        _ arguments: [String],
        input: Data = Data()
    ) throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = arguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        inputPipe.fileHandleForWriting.write(input)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            outputPipe.fileHandleForReading.readDataToEndOfFile(),
            errorPipe.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private func executableURL() throws -> URL {
        // Use the executable built beside this test bundle. Searching .build
        // can select an archived development engine or another scratch build.
        let direct = Bundle(for: CLIProcessTests.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("beztrace")
        if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
        XCTFail("SwiftPM did not build beztrace beside the current test bundle: \(direct.path)")
        throw CocoaError(.fileNoSuchFile)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
