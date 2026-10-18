// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import XCTest
@testable import BezierTraceCore

final class MatchSmoothingIntegrationTests: XCTestCase {
    func request(tolerance: Double = 1) -> MasterMatchRequest {
        let a=Outline(contours:[Contour(nodes:[.init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line,smooth:true),
            .init(x:130,y:0,type:.offcurve),.init(x:150,y:30,type:.offcurve),.init(x:150,y:50,type:.curve,smooth:true),
            .init(x:150,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a;b.contours[0].nodes[2].x+=0.5;b.contours[0].nodes[3].y-=0.5
        return .init(axis:.init(tag:"wght",locations:[100,900]),reference:.init(id:"a",outline:a),target:.init(id:"b",outline:b),
            options:.init(fitTolerance:tolerance,preserveStructure:true,smoothJoins:true))
    }
    func testIntegratedRepairMatchesStandaloneAndPreservesEvidence() throws {
        let q=request(),r=try OutlineMatcher.match(q)
        let expected=try JointMasterSmoother.smooth(.init(reference:q.reference.outline,target:q.target.outline,
            sourceTarget:q.target.outline,fitTolerance:q.options.fitTolerance))
        XCTAssertEqual(r.reference,q.reference);XCTAssertEqual(r.target.outline,expected.target)
        XCTAssertEqual(r.jointSmoothing?.status,.smoothed)
        XCTAssertEqual(r.sourceMasters,[q.reference,q.target])
        XCTAssertEqual(r.sourceHashes,try [OutlineMatcher.hash(q.reference.outline),OutlineMatcher.hash(q.target.outline)])
        XCTAssertEqual(r.interpolation.sampleCount,201);XCTAssertTrue(r.interpolation.issues.isEmpty)
        XCTAssertFalse(r.interpolation.nativeHOIVerified)
        XCTAssertEqual(r.jointSmoothing?.proposalDeviation?.upperBound,expected.report.proposalDeviation?.upperBound)
        XCTAssertTrue(r.contours.allSatisfy { $0.maximumTargetDeviation<=q.options.fitTolerance })
        var disabled=q;disabled.options.smoothJoins=false
        let unchanged=try OutlineMatcher.match(disabled)
        XCTAssertEqual(unchanged.target,q.target);XCTAssertNil(unchanged.jointSmoothing)
    }
    func testRefusalIsBlockingWithoutChangingTheBudget() throws {
        let q=request(tolerance:0.01)
        XCTAssertThrowsError(try OutlineMatcher.match(q)) { error in
            XCTAssertEqual((error as? MasterMatchError)?.diagnostic?.code,"joint-smoothing-refused")
            XCTAssertEqual((error as? MasterMatchError)?.diagnostic?.allowedDeviation,0.01)
        }
    }
    func testPairWorkflowSmoothsOnlyTheFinalResult() throws {
        var q=request();q.options.preserveStructure=false
        let r=try PairMatcher.match(reference:.outline(q.reference),target:.outline(q.target),unitsPerEm:q.unitsPerEm,
            axis:q.axis,options:q.options)
        XCTAssertEqual(r.results["direct"]?.reference,q.reference)
        XCTAssertEqual(r.results["direct"]?.jointSmoothing?.status,.smoothed)
        XCTAssertEqual(r.results["direct"]?.interpolation.sampleCount,201)
    }
    func testRawRasterBoundaryRemainsTheSourceEvenForAnUnchangedFit() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/matching/raster-v1")
        let image=MatchRasterInput(id:"b",imageData:try Data(contentsOf:root.appendingPathComponent("wide-rectangle.png")),
            transform:[128.0/1088,0,0,128.0/1088,0,0])
        let reference=MatchMaster(id:"a",outline:.init(contours:[.init(nodes:[.init(x:31.5,y:31.5,type:.line),
            .init(x:95.5,y:31.5,type:.line),.init(x:95.5,y:95.5,type:.line),.init(x:31.5,y:95.5,type:.line)])]))
        let q=RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[100,900]),
            reference:reference,images:[image],options:.init(smoothJoins:true))
        let r=try RasterMasterMatcher.match(q)
        XCTAssertEqual(r.reference,reference);XCTAssertEqual(r.jointSmoothing?.status,.unchanged)
        let bound=try XCTUnwrap(r.jointSmoothing?.proposalDeviation?.upperBound)
        XCTAssertGreaterThan(bound,0) // Measuring the fitted sourceMasters would incorrectly give zero.
        XCTAssertLessThanOrEqual(bound,1)
        XCTAssertEqual(r.rasterSources?.last?.maximumBoundaryDeviation,bound)
        XCTAssertEqual(bound,try RasterMasterMatcher.pairSourceDeviation(image,outline:r.target.outline,
            options:q.rasterOptions,tolerance:1).upperBound)
    }
    func testDefaultOptionsKeepTheirExistingWireContract() throws {
        let encoder=JSONEncoder()
        let old=try JSONSerialization.jsonObject(with:encoder.encode(MasterMatchOptions())) as! [String:Any]
        XCTAssertNil(old["smoothJoins"])
        let enabled=try JSONDecoder().decode(MasterMatchOptions.self,from:encoder.encode(request().options))
        XCTAssertTrue(enabled.smoothJoins)
    }
}
