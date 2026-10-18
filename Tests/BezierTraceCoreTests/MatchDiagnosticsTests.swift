// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class MatchDiagnosticsTests: XCTestCase {
    func path(_ points: [(Double,Double)]) -> Contour {
        .init(nodes:points.map { .init(x:$0.0,y:$0.1,type:.line) })
    }
    var box: Contour { path([(0,0),(100,0),(100,100),(0,100)]) }
    // Unequal lobes keep nonzero area, so the original crossing check is exercised.
    var crossing: Contour { path([(0,0),(100,100),(0,100),(80,0)]) }
    func request(_ a: Contour, _ b: Contour) -> MasterMatchRequest {
        .init(axis:.init(tag:"wght",locations:[400,700]),reference:.init(id:"regular",outline:.init(contours:[a])),
            target:.init(id:"bold",outline:.init(contours:[b])),options:.init(preserveStructure:true))
    }
    func testSourceCrossingHasRoleOriginalNodesAndAnalyticalLineIntersection() throws {
        for (a,b,role,id) in [(crossing,box,"reference","regular"),(box,crossing,"target","bold")] {
            XCTAssertThrowsError(try OutlineMatcher.match(request(a,b))) { error in
                let diagnostic = (error as? MasterMatchError)?.diagnostic
                XCTAssertEqual(diagnostic?.code,"self-intersection")
                XCTAssertEqual(diagnostic?.role,role); XCTAssertEqual(diagnostic?.masterID,id)
                XCTAssertEqual(diagnostic?.stage,"input"); XCTAssertEqual(diagnostic?.existedBeforeFitting,true)
                XCTAssertEqual(diagnostic?.locations?.map(\.segment),[0,2])
                XCTAssertEqual(diagnostic?.locations?.map(\.startNode),[0,2])
                XCTAssertEqual(diagnostic?.locations?.map(\.endNode),[1,3])
                XCTAssertEqual(diagnostic?.coordinates?[0] ?? 0,400.0/9,accuracy:1e-10)
                XCTAssertEqual(diagnostic?.coordinates?[1] ?? 0,400.0/9,accuracy:1e-10)
                XCTAssertEqual(diagnostic?.approximationTolerance,0.05)
            }
        }
    }
    func testFittedCrossingAndInterpolationRetainAttribution() throws {
        // Exercise the validation boundary on a newly introduced target crossing.
        XCTAssertThrowsError(try MatchGeometry.validate(MatchRing(crossing),unitsPerEm:1000,
            context:.init(stage:"fitted",role:"target",masterID:"bold",contour:3,existedBeforeFitting:false))) { error in
            let d = (error as? MasterMatchError)?.diagnostic
            XCTAssertEqual(d?.role,"target"); XCTAssertEqual(d?.stage,"fitted")
            XCTAssertEqual(d?.existedBeforeFitting,false); XCTAssertEqual(d?.locations?.map(\.contour),[3,3])
        }
        let report = try InterpolationValidator.validate(reference:.init(contours:[crossing]),target:.init(contours:[crossing]))
        let diagnostic = try XCTUnwrap(report.issues.first?.diagnostic)
        XCTAssertEqual(diagnostic.role,"interpolated"); XCTAssertEqual(diagnostic.stage,"interpolation")
        XCTAssertEqual(diagnostic.interpolationFactor,0)
        XCTAssertNil(diagnostic.existedBeforeFitting,"Standalone interpolation cannot infer original source history")
    }
    func testValidEndpointContactAndOverlapAreAdvisoryOnly() throws {
        for (shape,classification) in [
            (path([(0,0),(100,0),(100,100),(50,0),(0,100)]),"endpoint-contact"),
            (path([(0,0),(100,0),(100,100),(80,0),(20,0),(0,100)]),"overlap")] {
            XCTAssertNoThrow(try MatchGeometry.validate(MatchRing(shape),unitsPerEm:1000))
            let master = MatchMaster(id:"regular",outline:.init(contours:[shape]))
            let report = try MatchPreflight.inspect(.init(reference:master))
            XCTAssertTrue(report.eligible)
            XCTAssertTrue(report.diagnostics.contains { $0.classification == classification && !$0.blocking })
            // Existing compatible-outline review must still accept the contact.
            XCTAssertNoThrow(try OutlineMatcher.match(request(shape,shape)))
        }
    }
    func testNearCoincidenceAndInterContourOverlapDoNotAddRefusals() throws {
        for gap in [0.025,-10.0] {
            let shifted = Contour(nodes:box.nodes.map { .init(x:$0.x+100+gap,y:$0.y,type:$0.type) })
            let master = MatchMaster(id:"regular",outline:.init(contours:[box,shifted]))
            let report = try MatchPreflight.inspect(.init(reference:master))
            XCTAssertTrue(report.eligible)
            XCTAssertTrue(report.diagnostics.contains { $0.classification == (gap > 0 ? "near-coincidence" : "overlap") && !$0.blocking })
        }
    }
    func testPreflightBlocksCrossingAndBudgetWithoutMutatingReference() throws {
        let master = MatchMaster(id:"regular",outline:.init(contours:[crossing]))
        let report = try MatchPreflight.inspect(.init(reference:master))
        XCTAssertFalse(report.eligible); XCTAssertTrue(report.diagnostics.contains { $0.code == "self-intersection" && $0.blocking })
        XCTAssertFalse(report.rasterTopologyChecked)
        XCTAssertFalse(report.advisoryScanComplete,"Blocked sources must not allocate an extra flattened contact scan")
        let budget = try MatchPreflight.inspect(.init(reference:.init(id:"regular",outline:.init(contours:[box])),
            options:.init(fitTolerance:1,maxAdditionalOnCurveNodes:0,maxOnCurveNodes:3,maxNodes:3)))
        XCTAssertFalse(budget.eligible); XCTAssertFalse(budget.advisoryScanComplete); XCTAssertTrue(budget.diagnostics.contains { $0.code == "node-budget" })
        XCTAssertEqual(master.outline.contours,[crossing])
    }
    func testDiagnosticFlatteningExactlyMatchesValidationAndOriginalCubicIDs() throws {
        let ring = try MatchRing(.init(nodes:[.init(x:0,y:0,type:.line),
            .init(x:30,y:-20,type:.offcurve),.init(x:70,y:-20,type:.offcurve),.init(x:100,y:0,type:.curve),
            .init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line)]))
        let points = MatchGeometry.flatten(ring,tolerance:0.05)
        let edges = MatchGeometry.diagnosticEdges(ring,tolerance:0.05,contour:2)
        XCTAssertEqual(edges.map(\.start)+[edges.last!.end],points)
        XCTAssertTrue(edges.filter { $0.location.segment == 0 }.allSatisfy { $0.location.startNode == 0 && $0.location.endNode == 3 })
        XCTAssertEqual(edges.first?.location.parameterRange.first,0)
    }
    func testReferenceRasterTopologyPreflightUsesSameExtractionAndAffine() throws {
        let helper = RasterMasterMatchingTests()
        let image = try helper.image("rectangle.png",id:"reference-raster")
        let master = helper.box()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(master)
        let request = MatchPreflightRequest(reference:master,referenceImage:image)
        let report = try MatchPreflight.inspect(request)
        XCTAssertTrue(report.eligible); XCTAssertTrue(report.rasterTopologyChecked)
        XCTAssertEqual(report.rasterContours,1); XCTAssertEqual(report.rasterSource?.transform,image.transform)
        XCTAssertEqual(try encoder.encode(master),before)
        var mismatched = request
        let extra = Contour(nodes:master.outline.contours[0].nodes.map { .init(x:$0.x+200,y:$0.y,type:$0.type) })
        mismatched.reference.outline.contours.append(extra)
        let held = try MatchPreflight.inspect(mismatched)
        XCTAssertFalse(held.eligible); XCTAssertEqual(held.referenceContours,2); XCTAssertEqual(held.rasterContours,1)
        XCTAssertTrue(held.diagnostics.contains { $0.code == "reference-raster-topology" })
        let match = RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),
            reference:mismatched.reference,images:[image])
        XCTAssertThrowsError(try RasterMasterMatcher.match(match)) { error in
            guard case MasterMatchError.topology = error else { return XCTFail("Expected unchanged topology refusal: \(error)") }
        }
    }
    func testRasterRangesAndStrictFitAcceptanceRemainUnchanged() throws {
        let helper = RasterMasterMatchingTests()
        var request = RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),
            reference:helper.box(),images:[try helper.image("rectangle.png",id:"target")])
        for smoothing in [0.25,1,3] {
            request.rasterOptions.smoothing = smoothing
            XCTAssertNoThrow(try RasterMasterMatcher.match(request))
        }
        for smoothing in [0.249,3.001,4,Double.nan,Double.infinity] {
            request.rasterOptions.smoothing = smoothing
            XCTAssertThrowsError(try RasterMasterMatcher.match(request)) { error in
                let d = (error as? MasterMatchError)?.diagnostic
                XCTAssertEqual(d?.field,"rasterOptions.smoothing"); XCTAssertEqual(d?.allowedRange,[0.25,3])
                XCTAssertEqual(d?.mode,"trace-to-reference")
                XCTAssertFalse(String(describing:error).contains("joint tracing"))
            }
        }
        request.rasterOptions.smoothing = 1
        request.options.maxNodes = 3
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
        request.options.maxNodes = 64; request.options.fitTolerance = 0.00001
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
    }
}
