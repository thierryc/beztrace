// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCommand

final class MatchingCommandTests: XCTestCase {
    private var fixture: Data {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            return try Data(contentsOf: root.appendingPathComponent("Fixtures/matching/v1/shifted-start.json"))
        }
    }
    func testCapabilitiesAndMatchStreams() throws {
        let caps = CLIApplication.run(arguments: ["capabilities", "--format", "json"])
        XCTAssertEqual(caps.exitCode, 0)
        let value = try JSONSerialization.jsonObject(with: caps.standardOutput) as! [String: Any]
        XCTAssertEqual(value["matchSchemaVersion"] as? Int, 1)
        XCTAssertEqual(value["nativeHOI"] as? Bool, false)
        let result = CLIApplication.run(arguments: ["match", "-", "--json-errors"], standardInput: try fixture)
        XCTAssertEqual(result.exitCode, 0, String(decoding: result.standardError, as: UTF8.self))
        XCTAssertTrue(result.standardError.isEmpty)
        XCTAssertEqual(result.standardOutput, CLIApplication.run(arguments: ["match", "-"], standardInput: try fixture).standardOutput)
    }
    func testMalformedAndUnsupportedRequestsHaveEmptyStdout() throws {
        for args in [["match"], ["match", "-", "--oops"], ["capabilities", "--format", "svg"]] {
            let result = CLIApplication.run(arguments: args + ["--json-errors"])
            XCTAssertNotEqual(result.exitCode, 0); XCTAssertTrue(result.standardOutput.isEmpty)
        }
        var value = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        value["schemaVersion"] = 99
        let result = CLIApplication.run(arguments: ["match", "-", "--json-errors"], standardInput: try JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(result.exitCode, 2); XCTAssertTrue(result.standardOutput.isEmpty)
    }
}
