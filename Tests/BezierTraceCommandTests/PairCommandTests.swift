// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
import Foundation
@testable import BezierTraceCommand
final class PairCommandTests: XCTestCase {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/matching/pair-v1")
    func job(_ strategy: String="direct",kind: String="outline") throws -> [String:Any] {
        let transform=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Y-bold.transform.json")))
        let a: [String:Any]=["id":"regular","kind":"outline","path":root.appendingPathComponent("Y-regular.outline.json").path]
        let b: [String:Any]=kind=="outline" ? ["id":"bold","kind":"outline","path":root.appendingPathComponent("Y-bold.outline.json").path] : ["id":"bold","kind":"image","path":root.appendingPathComponent("Y-bold.png").path,"transform":transform]
        return ["schemaVersion":1,"unitsPerEm":1000,"axis":["tag":"wght","locations":[400,700]],"inputs":[a,b],"strategy":strategy]
    }
    func run(_ job: [String:Any],directory: URL,process: Bool = false) throws -> (CLIRunResult,URL) {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file=directory.appendingPathComponent("job.json"),out=directory.appendingPathComponent("result")
        try JSONSerialization.data(withJSONObject:job,options:[.sortedKeys]).write(to:file)
        let args=["match-pair",file.path,"--output-directory",out.path,"--json-errors"]
        if !process { return (CLIApplication.run(arguments:args),out) }
        let bin=Bundle(for:Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("beztrace")
        let p=Process();p.executableURL=bin;p.arguments=args
        let stdout=Pipe(),stderr=Pipe();p.standardOutput=stdout;p.standardError=stderr
        try p.run();p.waitUntilExit()
        return (.init(exitCode:p.terminationStatus,standardOutput:stdout.fileHandleForReading.readDataToEndOfFile(),standardError:stderr.fileHandleForReading.readDataToEndOfFile()),out)
    }
    func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pair-tests-"+UUID().uuidString) }
    func testRealProcessCleanWorkflowAndCollision() throws {
        let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
        let (r,out)=try run(job("smart"),directory:dir,process:true)
        XCTAssertEqual(r.exitCode,0,String(decoding:r.standardError,as:UTF8.self))
        let files=try FileManager.default.contentsOfDirectory(atPath:out.path)
        for f in ["comparison.json","recommended.master-set.json","reference.outline.json","target.outline.json","index.html","direct.proof.svg"] { XCTAssertTrue(files.contains(f)) }
        let before=try Data(contentsOf:out.appendingPathComponent("recommended.master-set.json"))
        let (collision,_)=try run(job(),directory:dir)
        XCTAssertEqual(collision.exitCode,2);XCTAssertTrue(collision.standardOutput.isEmpty)
        XCTAssertEqual(before,try Data(contentsOf:out.appendingPathComponent("recommended.master-set.json")))
    }
    func testMixedAndImagesWithExplicitAbsoluteBudgets() throws {
        for images in [false,true] {
            let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
            var j=try job("smart",kind:"image")
            if images {
                var inputs=j["inputs"] as! [[String:Any]]
                inputs[0]=["id":"regular","kind":"image","path":root.appendingPathComponent("Y-regular.png").path,"transform":try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Y-regular.transform.json")))]
                j["inputs"]=inputs;j["options"]=["maxOnCurveNodes":64,"maxNodes":160]
            }
            let (r,out)=try run(j,directory:dir)
            XCTAssertEqual(r.exitCode,0,String(decoding:r.standardError,as:UTF8.self))
            let report=try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("comparison.json"))) as! [String:Any]
            XCTAssertEqual((report["inputFiles"] as! [[String:Any]]).count,2)
        }
    }
    func testInvalidFieldsAndForbiddenRetracingCreateNoDirectory() throws {
        for change in ["unknown","retrace","budget"] {
            let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
            var j=try job()
            if change=="unknown" { j["unexpected"]=true }
            if change=="retrace" { j["strategy"]="retrace-both" }
            if change=="budget" { j["options"]=["maxNodes":-1] }
            let (r,out)=try run(j,directory:dir)
            XCTAssertEqual(r.exitCode,2);XCTAssertTrue(r.standardOutput.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath:out.path))
        }
    }
    func testMissingAndMalformedOutlineFilesAreInputFailures() throws {
        for malformed in [false,true] {
            let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let source=dir.appendingPathComponent("source.outline.json")
            if malformed { try Data("invalid outline".utf8).write(to:source) }
            var j=try job();var inputs=j["inputs"] as! [[String:Any]];inputs[1]["path"]=source.path;j["inputs"]=inputs
            let (r,out)=try run(j,directory:dir)
            XCTAssertEqual(r.exitCode,3);XCTAssertTrue(r.standardOutput.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath:out.path))
        }
    }
    func testGeometryRefusalContainsReportButNoMatchedPaths() throws {
        let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
        var j=try job();var inputs=j["inputs"] as! [[String:Any]];inputs[0]["path"]=root.appendingPathComponent("R-regular.outline.json").path;j["inputs"]=inputs
        let (r,out)=try run(j,directory:dir)
        XCTAssertEqual(r.exitCode,5);XCTAssertTrue(r.standardOutput.isEmpty)
        let files=try FileManager.default.contentsOfDirectory(atPath:out.path)
        XCTAssertTrue(files.contains("comparison.json"));XCTAssertFalse(files.contains { $0.hasSuffix(".master-set.json") })
    }
    func testRepeatedProcessReportsAndMasterBytes() throws {
        let a=temp(),b=temp();defer { try? FileManager.default.removeItem(at:a);try? FileManager.default.removeItem(at:b) }
        let (ar,ao)=try run(job("smart"),directory:a,process:true),(br,bo)=try run(job("smart"),directory:b,process:true)
        XCTAssertEqual(ar.exitCode,0);XCTAssertEqual(br.exitCode,0)
        for f in ["comparison.json","recommended.master-set.json","direct.proof.svg"] { XCTAssertEqual(try Data(contentsOf:ao.appendingPathComponent(f)),try Data(contentsOf:bo.appendingPathComponent(f))) }
    }
    func testConflictingPointPolicyAndInapplicableFlagExplainTheField() throws {
        for (options,field) in [(["maxAdditionalOnCurveNodes":2],"options.maxAdditionalOnCurveNodes"),
                                (["preserveStructure":true],"options.preserveStructure"),
                                (["maxNodes":-1],"options.maxNodes")] as [([String:Any],String)] {
            let dir=temp();defer { try? FileManager.default.removeItem(at:dir) }
            var j=try job();j["options"]=options
            let (r,out)=try run(j,directory:dir,process:true)
            XCTAssertEqual(r.exitCode,2);XCTAssertTrue(r.standardOutput.isEmpty)
            let error=try JSONSerialization.jsonObject(with:r.standardError) as! [String:Any]
            let diagnostic=(error["error"] as! [String:Any])["diagnostic"] as! [String:Any]
            XCTAssertEqual(diagnostic["field"] as? String,field)
            XCTAssertFalse(FileManager.default.fileExists(atPath:out.path))
        }
    }
}
