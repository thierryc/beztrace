// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import XCTest
import BezierTraceCore
@testable import BezierTraceCommand

final class SmoothingCommandTests: XCTestCase {
    func request(_ tolerance: Double = 5) -> JointSmoothingRequest {
        let a=Outline(contours:[Contour(nodes:[.init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line,smooth:true),
            .init(x:130,y:0,type:.offcurve),.init(x:150,y:30,type:.offcurve),.init(x:150,y:50,type:.curve,smooth:true),
            .init(x:150,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a;b.contours[0].nodes[2].x+=5;b.contours[0].nodes[3].y-=5
        return .init(reference:a,target:b,sourceTarget:b,fitTolerance:tolerance)
    }
    func testStdinSmoothingAndAtomicRefusal() throws {
        for tolerance in [0.01,5] {
            let input=request(tolerance),bytes=try JSONEncoder().encode(input)
            let output=CLIApplication.run(arguments:["smooth-masters","-","--json-errors"],standardInput:bytes)
            let r=try JSONDecoder().decode(JointSmoothingResult.self,from:output.standardOutput)
            XCTAssertEqual(output.exitCode,tolerance<1 ? 5 : 0)
            XCTAssertEqual(r.reference,input.reference)
            XCTAssertEqual(r.unitsPerEm,input.unitsPerEm);XCTAssertEqual(r.fitTolerance,tolerance)
            if tolerance<1 { XCTAssertEqual(r.target,input.target);XCTAssertEqual(r.report.status,.refused) }
            else { XCTAssertEqual(r.report.status,.smoothed) }
        }
    }
    func testInvalidRequestAndUnknownFields() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(request())) as! [String:Any]
        for key in ["sourceTarget","unknown"] {
            var invalid=object
            if key=="sourceTarget" { invalid.removeValue(forKey:key) } else { invalid[key]=true }
            let output=CLIApplication.run(arguments:["smooth-masters","-","--json-errors"],standardInput:try JSONSerialization.data(withJSONObject:invalid))
            XCTAssertEqual(output.exitCode,2);XCTAssertTrue(output.standardOutput.isEmpty)
            XCTAssertNotNil(try JSONSerialization.jsonObject(with:output.standardError))
        }
        object["schemaVersion"]=2
        XCTAssertEqual(CLIApplication.run(arguments:["smooth-masters","-"],standardInput:try JSONSerialization.data(withJSONObject:object)).exitCode,2)
    }
    func testRealExecutableFileExchange() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("joint-smoothing-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let input=dir.appendingPathComponent("request.json"),output=dir.appendingPathComponent("result.json")
        try JSONEncoder().encode(request()).write(to:input)
        let p=Process()
        p.executableURL=Bundle(for:Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("beztrace")
        p.arguments=["smooth-masters",input.path,"--output",output.path,"--json-errors"]
        let stdout=Pipe(),stderr=Pipe();p.standardOutput=stdout;p.standardError=stderr
        try p.run();p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus,0,String(decoding:stderr.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))
        let result=try JSONDecoder().decode(JointSmoothingResult.self,from:Data(contentsOf:output))
        XCTAssertEqual(result.report.status,.smoothed)
        XCTAssertTrue(stdout.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
    func testMatchingCommandIntegratesRepairAndAdvertisesSupport() throws {
        let input=request()
        var q=MasterMatchRequest(axis:.init(tag:"wght",locations:[100,900]),reference:.init(id:"a",outline:input.reference),
            target:.init(id:"b",outline:input.target),options:.init(fitTolerance:5,preserveStructure:true,smoothJoins:true))
        let output=CLIApplication.run(arguments:["match","-","--json-errors"],standardInput:try JSONEncoder().encode(q))
        XCTAssertEqual(output.exitCode,0,String(decoding:output.standardError,as:UTF8.self))
        let r=try JSONDecoder().decode(MasterMatchResult.self,from:output.standardOutput)
        XCTAssertEqual(r.reference,q.reference);XCTAssertEqual(r.jointSmoothing?.status,.smoothed)
        q.options.fitTolerance=0.01
        let refused=CLIApplication.run(arguments:["match","-","--json-errors"],standardInput:try JSONEncoder().encode(q))
        XCTAssertNotEqual(refused.exitCode,0);XCTAssertTrue(refused.standardOutput.isEmpty)
        let caps=CLIApplication.run(arguments:["capabilities","--format","json"])
        let value=try JSONSerialization.jsonObject(with:caps.standardOutput) as! [String:Any]
        XCTAssertEqual(value["matchSmoothingVersion"] as? Int,1)
        XCTAssertEqual(value["hybridFittingVersion"] as? Int,1)
    }
}
