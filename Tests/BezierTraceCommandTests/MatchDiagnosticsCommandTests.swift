// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import BezierTraceCore
import XCTest
@testable import BezierTraceCommand

final class MatchDiagnosticsCommandTests: XCTestCase {
    let reference = MatchMaster(id:"regular",outline:.init(contours:[.init(nodes:[
        .init(x:31.5,y:31.5,type:.line),.init(x:95.5,y:31.5,type:.line),
        .init(x:95.5,y:95.5,type:.line),.init(x:31.5,y:95.5,type:.line)])]))
    func rasterRequest() throws -> RasterMasterMatchRequest {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf:root.appendingPathComponent("Fixtures/matching/raster-v1/rectangle.png"))
        return .init(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),reference:reference,
            images:[.init(id:"bold",imageData:data,transform:[128.0/1088,0,0,128.0/1088,0,0])])
    }
    func testInvalidSmoothingErrorIsStructuredAndKeepsExitCodeAndEmptyOutput() throws {
        var request = try rasterRequest(); request.rasterOptions.smoothing = 4
        for command in ["match","match-plan"] {
            let failed = CLIApplication.run(arguments:[command,"-","--json-errors"],standardInput:try JSONEncoder().encode(request))
            XCTAssertEqual(failed.exitCode,2); XCTAssertTrue(failed.standardOutput.isEmpty)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with:failed.standardError) as? [String:Any])
            let error = try XCTUnwrap(root["error"] as? [String:Any])
            let detail = try XCTUnwrap(error["diagnostic"] as? [String:Any])
            XCTAssertEqual(detail["field"] as? String,"rasterOptions.smoothing")
            XCTAssertEqual(detail["providedValue"] as? String,"4.0")
            XCTAssertEqual(detail["allowedRange"] as? [Double],[0.25,3])
            XCTAssertEqual(detail["mode"] as? String,"trace-to-reference")
            XCTAssertFalse((error["message"] as? String ?? "").contains("joint tracing"))
        }
        request.rasterOptions.smoothing = 1
        let pass = CLIApplication.run(arguments:["match","-","--json-errors"],standardInput:try JSONEncoder().encode(request))
        XCTAssertEqual(pass.exitCode,0); XCTAssertTrue(pass.standardError.isEmpty)
        XCTAssertEqual(pass.standardOutput,CLIApplication.run(arguments:["match","-"],standardInput:try JSONEncoder().encode(request)).standardOutput)
    }
    func testPreserveStructureIsAFieldSpecificVectorReviewOption() throws {
        var request=try rasterRequest(); request.options.preserveStructure=true
        let failed=CLIApplication.run(arguments:["match","-","--json-errors"],standardInput:try JSONEncoder().encode(request))
        XCTAssertEqual(failed.exitCode,2); XCTAssertTrue(failed.standardOutput.isEmpty)
        let root=try XCTUnwrap(JSONSerialization.jsonObject(with:failed.standardError) as? [String:Any])
        let error=try XCTUnwrap(root["error"] as? [String:Any])
        let detail=try XCTUnwrap(error["diagnostic"] as? [String:Any])
        XCTAssertEqual(detail["field"] as? String,"options.preserveStructure")
        XCTAssertTrue((error["message"] as? String ?? "").contains("referencePolicy=fixed"))
        XCTAssertFalse((error["message"] as? String ?? "").contains("joint tracing"))
    }
    func testReferenceAndTargetCrossingErrorHasLocationWithoutResultGeometry() throws {
        let crossing = MatchMaster(id:"crossing",outline:.init(contours:[.init(nodes:[
            .init(x:0,y:0,type:.line),.init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line),.init(x:80,y:0,type:.line)])]))
        for role in ["reference","target"] {
            let request = MasterMatchRequest(axis:.init(tag:"wght",locations:[400,700]),
                reference:role == "reference" ? crossing : reference,target:role == "target" ? crossing : reference)
            let failure = CLIApplication.run(arguments:["match","-","--json-errors"],standardInput:try JSONEncoder().encode(request))
            XCTAssertEqual(failure.exitCode,5); XCTAssertTrue(failure.standardOutput.isEmpty)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with:failure.standardError) as? [String:Any])
            let error = try XCTUnwrap(root["error"] as? [String:Any])
            let detail = try XCTUnwrap(error["diagnostic"] as? [String:Any])
            XCTAssertEqual(detail["role"] as? String,role); XCTAssertEqual(detail["masterID"] as? String,"crossing")
            XCTAssertEqual(detail["existedBeforeFitting"] as? Bool,true)
            XCTAssertEqual((detail["locations"] as? [[String:Any]])?.count,2)
        }
    }
    func testPreflightStreamsReportsIneligibilityAndRejectsMalformedRequests() throws {
        let raster = try rasterRequest()
        let request = MatchPreflightRequest(reference:reference,referenceImage:raster.images[0])
        let encoded = try JSONEncoder().encode(request)
        let pass = CLIApplication.run(arguments:["match-preflight","-","--json-errors"],standardInput:encoded)
        XCTAssertEqual(pass.exitCode,0); XCTAssertTrue(pass.standardError.isEmpty)
        let report = try JSONDecoder().decode(MatchPreflightResult.self,from:pass.standardOutput)
        XCTAssertTrue(report.eligible); XCTAssertTrue(report.rasterTopologyChecked)
        XCTAssertEqual(report.kind,"beztrace-match-preflight")
        XCTAssertEqual(pass.standardOutput,CLIApplication.run(arguments:["match-preflight","-"],standardInput:encoded).standardOutput)
        var blocked = request; blocked.options.maxNodes = 3
        let held = CLIApplication.run(arguments:["match-preflight","-"],standardInput:try JSONEncoder().encode(blocked))
        XCTAssertEqual(held.exitCode,0)
        XCTAssertFalse(try JSONDecoder().decode(MatchPreflightResult.self,from:held.standardOutput).eligible)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        object["target"] = object["reference"]
        let malformed = CLIApplication.run(arguments:["match-preflight","-","--json-errors"],standardInput:try JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(malformed.exitCode,3); XCTAssertTrue(malformed.standardOutput.isEmpty)
        blocked.schemaVersion = 99
        let invalid = CLIApplication.run(arguments:["match-preflight","-","--json-errors"],standardInput:try JSONEncoder().encode(blocked))
        XCTAssertEqual(invalid.exitCode,2); XCTAssertTrue(invalid.standardOutput.isEmpty)
    }
}
