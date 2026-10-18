// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
import CryptoKit
@testable import BezierTraceCore
final class PairMatchingTests: XCTestCase {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/matching/pair-v1")
    let axis=MatchAxis(tag:"wght",locations:[400,700])
    func master(_ glyph: String,_ weight: String) throws -> MatchMaster {
        .init(id:weight,outline:try JSONDecoder().decode(Outline.self,from:Data(contentsOf:root.appendingPathComponent("\(glyph)-\(weight).outline.json"))))
    }
    func options(_ m: MatchMaster,policy: ReferencePolicy = .fixed) -> MasterMatchOptions {
        .init(referencePolicy:policy,fitTolerance:1,maxAdditionalOnCurveNodes:policy == .fixed ? 0 : 40,maxOnCurveNodes:policy == .fixed ? m.outline.contours.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count } : 64,maxNodes:policy == .fixed ? m.outline.contours.reduce(0) { $0+$1.nodes.count } : 160)
    }
    func testFrozenControlsAndFixedVectors() throws {
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as! [String:Any]
        for (file,hash) in manifest["files"] as! [String:String] { XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:root.appendingPathComponent(file))).map { String(format:"%02x",$0) }.joined(),hash) }
        for g in ["R","Y"] {
            let a=try master(g,"regular"),b=try master(g,"bold")
            let output=try PairMatcher.match(reference:.outline(a),target:.outline(b),unitsPerEm:1000,axis:axis,options:options(a))
            XCTAssertEqual(output.report.recommendedRoute,"direct",String(describing:output.report.candidates))
            XCTAssertEqual(output.results["direct"]?.reference.outline,a.outline)
        }
    }
    func testRendererNonzeroCounterOrientationPlacementAndIdentity() throws {
        for g in ["R","Y"] {
            let a=try master(g,"regular"),b=try master(g,"bold")
            for m in [a,b] {
                let r=try PairOutlineRenderer.render(m,unitsPerEm:1000)
                XCTAssertEqual(r.image.imageData,try PairOutlineRenderer.render(m,unitsPerEm:1000).image.imageData)
                let d=try RasterMasterMatcher.pairSourceDeviation(r.image,outline:m.outline,options:.init(),tolerance:1)
                XCTAssertLessThan(d.upperBound,0.6,"Orientation and explicit inverse placement must recover the original source")
                if let export=ProcessInfo.processInfo.environment["BEZTRACE_PAIR_EXPORT"] {
                    let dir=URL(fileURLWithPath:export);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                    try r.image.imageData.write(to:dir.appendingPathComponent("\(g)-\(m.id).png"))
                    let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys,.prettyPrinted]
                    try enc.encode(r.image.transform).write(to:dir.appendingPathComponent("\(g)-\(m.id).transform.json"))
                }
            }
        }
    }
    func testSmartLockedReferenceRoutesAndReproducibility() throws {
        let a=try master("Y","regular"),b=try master("Y","bold")
        func run() throws -> PairMatchOutput { try PairMatcher.match(reference:.outline(a),target:.outline(b),unitsPerEm:1000,axis:axis,options:options(a),strategy:.smart) }
        let o=try run();XCTAssertEqual(o.report.candidates.map(\.route),["direct","retrace-target"])
        XCTAssertEqual(o.report.recommendedRoute,"direct")
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        XCTAssertEqual(try encoder.encode(o.report),try encoder.encode(run().report))
        XCTAssertTrue(o.report.candidates.filter(\.accepted).allSatisfy { $0.referenceUnchanged==true && $0.sourceDeviations.allSatisfy { $0.upperBound<=1 } })
    }
    func testEveryInputCombinationAndUnlockedRetraceReports() throws {
        for g in ["R","Y"] {
            let a=try master(g,"regular"),b=try master(g,"bold"),ar=try PairOutlineRenderer.render(a,unitsPerEm:1000).image,br=try PairOutlineRenderer.render(b,unitsPerEm:1000).image
            let mixed=try PairMatcher.match(reference:.outline(a),target:.image(br),unitsPerEm:1000,axis:axis,options:options(a))
            XCTAssertNotNil(mixed.report.recommendedRoute,String(describing:mixed.report.candidates))
            let both=try PairMatcher.match(reference:.image(ar),target:.image(br),unitsPerEm:1000,axis:axis,options:options(a,policy:.sharedSubdivision),strategy:.smart)
            XCTAssertEqual(both.report.candidates.map(\.route),["joint-images","sequential-images"])
            XCTAssertNotNil(both.report.recommendedRoute,String(describing:both.report.candidates))
            let rebuilt=try PairMatcher.match(reference:.outline(a),target:.outline(b),unitsPerEm:1000,axis:axis,options:options(a,policy:.sharedSubdivision),strategy:.retraceBoth)
            XCTAssertEqual(rebuilt.report.candidates.map(\.route),["retrace-both"])
            XCTAssertNotNil(rebuilt.report.recommendedRoute,String(describing:rebuilt.report.candidates))
            XCTAssertFalse(rebuilt.report.candidates[0].envelopeAdjustments.isEmpty)
            XCTAssertTrue(rebuilt.report.candidates[0].sourceDeviations.allSatisfy { $0.upperBound<=1 })
            XCTAssertTrue(rebuilt.report.candidates[0].envelopeAdjustments.allSatisfy { $0.method=="local-span-constraint" && $0.scaleY==1 && $0.translateY==0 })
            // Measured optimizer refusals remain useful evidence; no false success.
            XCTAssertEqual(rebuilt.results.isEmpty,!rebuilt.report.candidates[0].accepted)
        }
    }
    func testRefusalsAndInvalidOptionsAreDistinct() throws {
        let a=try master("R","regular"),y=try master("Y","bold")
        let mismatch=try PairMatcher.match(reference:.outline(a),target:.outline(y),unitsPerEm:1000,axis:axis,options:options(a))
        XCTAssertNil(mismatch.report.recommendedRoute);XCTAssertTrue(mismatch.results.isEmpty)
        XCTAssertTrue(mismatch.report.candidates[0].refusal!.contains("Topology"))
        XCTAssertThrowsError(try PairMatcher.match(reference:.outline(a),target:.outline(a),unitsPerEm:1000,axis:axis,options:options(a)))
        XCTAssertThrowsError(try PairMatcher.match(reference:.outline(a),target:.outline(y),unitsPerEm:1000,axis:axis,options:options(a),strategy:.retraceBoth))
        var small=options(a);small.maxNodes=3
        let budget=try PairMatcher.match(reference:.outline(a),target:.outline(try master("R","bold")),unitsPerEm:1000,axis:axis,options:small)
        XCTAssertNil(budget.report.recommendedRoute);XCTAssertTrue(budget.report.candidates[0].refusal!.contains("budget"))
        var crossed=y;crossed.outline.contours[0].nodes=[.init(x:0,y:0,type:.line),.init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line),.init(x:100,y:0,type:.line)]
        XCTAssertThrowsError(try PairMatcher.match(reference:.outline(a),target:.outline(crossed),unitsPerEm:1000,axis:axis,options:options(a)))
    }
    func testSmartFidelityTieEconomyAndStableOrder() {
        func candidate(_ route: String,_ lower: Double,_ upper: Double,_ nodes: Int) -> PairCandidateReport {
            var c=PairCandidateReport(route:route,accepted:true)
            c.sourceDeviations=[.init(lowerBound:0,upperBound:0,uncertainty:0),.init(lowerBound:lower,upperBound:upper,uncertainty:upper-lower)]
            c.totalNodes=nodes;c.onCurveNodes=nodes;c.excessSmoothJoinResidual=0;return c
        }
        let routes=["direct","retrace-target","retrace-both"]
        let a=candidate("direct",0.70,0.73,18),b=candidate("retrace-target",0.71,0.75,12),c=candidate("retrace-both",0.90,0.94,6)
        let ranking=PairMatcher.rank([a,b,c],routes:routes)
        XCTAssertEqual(ranking.tiedCount,2)
        XCTAssertEqual(ranking.reports.first?.route,"retrace-target","Economy breaks overlapping fidelity intervals")
        XCTAssertFalse(ranking.reports.contains { $0.route=="retrace-both" },"Fewer nodes cannot beat significantly worse fidelity")
        var exact=b;exact.totalNodes=a.totalNodes;exact.onCurveNodes=a.onCurveNodes;exact.sourceDeviations=a.sourceDeviations
        XCTAssertEqual(PairMatcher.rank([exact,a],routes:routes).reports.first?.route,"direct","Exact ties use stable documented route order")
    }
    func testIndependentBoundFindsUnsampledLineInteriorDeviation() throws {
        let a=[Point2D(x:0,y:0),Point2D(x:10,y:0),Point2D(x:0,y:0)]
        let b=[Point2D(x:0,y:0),Point2D(x:5,y:2),Point2D(x:10,y:0),Point2D(x:0,y:0)]
        let m=try PairGeometry.measure(a,b,tolerance:1,flattenAllowance:0)
        XCTAssertGreaterThanOrEqual(m.upperBound,2);XCTAssertLessThanOrEqual(m.lowerBound,2)
        XCTAssertLessThanOrEqual(m.uncertainty,0.026)
    }
    func testSharedConfigurationDefaultsAndExplicitGrowth() throws {
        let a=try master("R","regular"),on=a.outline.contours.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count },total=a.outline.contours.reduce(0) { $0+$1.nodes.count }
        let fixed=try PairMatchConfiguration().resolved(reference:.outline(a),unitsPerEm:1000)
        XCTAssertEqual(fixed.referencePolicy,.fixed);XCTAssertEqual(fixed.fitTolerance,1)
        XCTAssertEqual(fixed.maxOnCurveNodes,on);XCTAssertEqual(fixed.maxNodes,total)
        XCTAssertThrowsError(try PairMatchConfiguration(maxAdditionalOnCurveNodes:2).resolved(reference:.outline(a),unitsPerEm:1000)) { error in
            XCTAssertEqual((error as? MasterMatchError)?.diagnostic?.field,"options.maxAdditionalOnCurveNodes")
        }
        XCTAssertThrowsError(try PairMatchConfiguration(referencePolicy:.sharedSubdivision).resolved(reference:.outline(a),unitsPerEm:1000))
        for added in [1,2] {
            let config=PairMatchConfiguration(referencePolicy:.sharedSubdivision,maxAdditionalOnCurveNodes:added,maxOnCurveNodes:on+added,maxNodes:total+3*added)
            let o=try config.resolved(reference:.outline(a),unitsPerEm:1000)
            XCTAssertEqual(o.fitTolerance,1);XCTAssertEqual(o.maxAdditionalOnCurveNodes,added)
            let result=try PairMatcher.match(reference:.outline(a),target:.outline(try master("R","bold")),unitsPerEm:1000,axis:axis,options:o)
            XCTAssertNotNil(result.report.recommendedRoute)
            XCTAssertLessThanOrEqual(result.report.candidates[0].onCurveNodes!,on+added)
            XCTAssertLessThanOrEqual(result.report.candidates[0].totalNodes!,total+3*added)
        }
    }
    func testGeometryIsIndependentOfNamesAndWritingDirection() throws {
        let a=try master("R","regular"),b=try master("R","bold")
        for reflected in [false,true] {
            func moved(_ m: MatchMaster,id: String) -> MatchMaster {
                .init(id:id,outline:.init(contours:m.outline.contours.map { c in
                    .init(nodes:c.nodes.map { n in .init(x:(reflected ? -n.y : n.y)+100,y:n.x-50,type:n.type,smooth:n.smooth) })
                }))
            }
            let reference=moved(a,id:"مرجع"),target=moved(b,id:"目标")
            let result=try PairMatcher.match(reference:.outline(reference),target:.outline(target),unitsPerEm:1000,axis:axis,options:options(reference))
            XCTAssertEqual(result.results["direct"]?.reference.outline,reference.outline)
            XCTAssertEqual(result.results["direct"]?.target.outline,target.outline)
        }
    }
}
