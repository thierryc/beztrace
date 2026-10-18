// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import CryptoKit
import XCTest
@testable import BezierTraceCore

final class RasterFitInvestigationTests: XCTestCase {
    /// Explicit private replay; no owner artwork is bundled with public tests.
    func testPrivateHandoffEvidence() throws {
        let environment=ProcessInfo.processInfo.environment
        guard let handoff=environment["BEZTRACE_PRIVATE_HANDOFF"],
              let destination=environment["BEZTRACE_FIT_EVIDENCE"] else {
            throw XCTSkip("Private handoff replay requires explicit input and evidence directories")
        }
        let root=URL(fileURLWithPath:handoff), output=URL(fileURLWithPath:destination)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as? [String:Any])
        let entries=try XCTUnwrap(manifest["files"] as? [[String:Any]])
        for item in entries {
            let path=try XCTUnwrap(item["path"] as? String), expected=try XCTUnwrap(item["sha256"] as? String)
            let bytes=try Data(contentsOf:root.appendingPathComponent(path))
            XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),expected)
        }
        for name in ["regular-identity","primary-bold","alternate-bold","primary-correspondence","alternate-correspondence","passing-r-control"] {
            let data=try Data(contentsOf:root.appendingPathComponent("fixtures/\(name).json"))
            let request=try JSONDecoder().decode(RasterMasterMatchRequest.self,from:data)
            var evidence:[RasterMasterMatcher.FitEvidence]=[]
            do {
                let result=try RasterMasterMatcher.match(request,observing:{ evidence.append($0) })
                XCTAssertEqual(result.reference.outline,request.reference!.outline)
                XCTAssertEqual(result.target.outline.contours.map { $0.nodes.map(\.type) },request.reference!.outline.contours.map { $0.nodes.map(\.type) })
                XCTAssertEqual(result.nodeBudget?.totalNodes,request.options.maxNodes)
                XCTAssertLessThanOrEqual(result.rasterSources!.first!.maximumBoundaryDeviation,request.options.fitTolerance)
                XCTAssertEqual(result.rasterSources!.first!.transform,request.images[0].transform)
                let interleaved=try InterpolationValidator.validate(reference:result.reference.outline,target:result.target.outline,
                    unitsPerEm:1000,intervals:200)
                XCTAssertFalse(interleaved.issues.contains { $0.message != "smooth join tangency residual" })
                if name != "passing-r-control" {
                    let targetRings=try result.target.outline.contours.map(MatchRing.init)
                    let top=targetRings.map { $0.bounds.maxY }.max()!
                    let bottom=targetRings.map { $0.bounds.minY }.min()!
                    XCTAssertLessThanOrEqual(top,716+1e-9)
                    XCTAssertGreaterThanOrEqual(bottom,-1e-9)
                    XCTAssertEqual(result.nodeBudget?.resultOnCurves,22)
                }
                try MasterMatchSerializer.json(result).write(to:output.appendingPathComponent("\(name).result.json"))
            } catch {
                XCTFail("Private regression \(name): \(error)")
                try Data(String(describing:error).utf8).write(to:output.appendingPathComponent("\(name).error.txt"))
            }
            try encoder.encode(evidence).write(to:output.appendingPathComponent("\(name).evidence.json"))

        }
    }
}
