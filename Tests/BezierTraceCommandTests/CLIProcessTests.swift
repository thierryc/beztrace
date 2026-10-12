// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
import BezierTraceCore

final class CLIProcessTests: XCTestCase {
    func testMatchingDiagnosticsAndPreflightThroughRealProcess() throws {
        let data = try Data(contentsOf:repositoryRoot.appendingPathComponent("Tests/Fixtures/matching/raster-v1/rectangle.png"))
        let master = MatchMaster(id:"regular",outline:.init(contours:[.init(nodes:[
            .init(x:31.5,y:31.5,type:.line),.init(x:95.5,y:31.5,type:.line),
            .init(x:95.5,y:95.5,type:.line),.init(x:31.5,y:95.5,type:.line)])]))
        let image = MatchRasterInput(id:"bold",imageData:data,transform:[128.0/1088,0,0,128.0/1088,0,0])
        var request = RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),reference:master,images:[image])
        request.rasterOptions.smoothing = 4
        let invalid = try launch(["match","-","--json-errors"],input:JSONEncoder().encode(request))
        XCTAssertEqual(invalid.status,2); XCTAssertTrue(invalid.output.isEmpty)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with:invalid.error) as? [String:Any])
        let detail = try XCTUnwrap((envelope["error"] as? [String:Any])?["diagnostic"] as? [String:Any])
        XCTAssertEqual(detail["field"] as? String,"rasterOptions.smoothing")
        let preflight = try JSONEncoder().encode(MatchPreflightRequest(reference:master,referenceImage:image))
        let first = try launch(["match-preflight","-"],input:preflight)
        let second = try launch(["match-preflight","-"],input:preflight)
        XCTAssertEqual(first.status,0); XCTAssertTrue(first.error.isEmpty); XCTAssertEqual(first.output,second.output)
        XCTAssertTrue(try JSONDecoder().decode(MatchPreflightResult.self,from:first.output).eligible)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let output = directory.appendingPathComponent("report.json")
        let saved = try launch(["match-preflight","-","--output",output.path],input:preflight)
        XCTAssertEqual(saved.status,0); XCTAssertTrue(saved.output.isEmpty); XCTAssertTrue(saved.error.isEmpty)
        XCTAssertEqual(try Data(contentsOf:output),first.output)
        // A refusal must not replace an existing output file.
        let failed = try launch(["match","-","--output",output.path,"--json-errors"],input:JSONEncoder().encode(request))
        XCTAssertEqual(failed.status,2); XCTAssertTrue(failed.output.isEmpty)
        XCTAssertEqual(try Data(contentsOf:output),first.output)
    }
    func testBuiltExecutableVersionAndFailureStreams() throws {
        let version = try launch(["--version"])
        XCTAssertEqual(version.status, 0)
        XCTAssertEqual(String(decoding: version.output, as: UTF8.self), "beztrace 0.2.0-dev.1\n")
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
