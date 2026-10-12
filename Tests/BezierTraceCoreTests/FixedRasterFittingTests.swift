// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class FixedRasterFittingTests: XCTestCase {
    func error(_ curve: CubicBezier,_ points: [Point2D]) -> Double {
        let poly=(0...1024).map { curve.point(at:Double($0)/1024) }
        return max(points.map { MatchGeometry.distance($0,to:poly) }.max() ?? 0,
                   poly.map { MatchGeometry.distance($0,to:points) }.max() ?? 0)
    }
    func bowedLine(_ amplitude: Double) -> [Point2D] {
        (0...100).map { i in
            let t=Double(i)/100
            return .init(x:100+amplitude*4*t*(1-t),y:100*t)
        }
    }
    func testMinimumWidthLineChangesOrientationAndCentersResiduals() throws {
        let points=bowedLine(1.6).enumerated().map { i,p in
            Point2D(x:p.x+Double(i)*0.007,y:p.y)
        }
        let chord=lineCubic(from:points[0],to:points.last!)
        let fit=try XCTUnwrap(MatchingLineFitter.fit(points))
        XCTAssertGreaterThan(error(chord,points),1)
        XCTAssertLessThanOrEqual(fit.lowerBound,0.801)
        XCTAssertLessThan(error(fit.curve,points),0.81)
    }
    func testTrueLineRepresentationLimitHasIndependentLowerBound() throws {
        let fit=try XCTUnwrap(MatchingLineFitter.fit(bowedLine(2.4)))
        XCTAssertGreaterThan(fit.lowerBound,1.19,"No infinite line, hence no finite line, can fit this entire span at 1u")
        XCTAssertNil(MatchingLineFitter.fit([.init(x:0,y:0),.init(x:0,y:0)]))
    }
    func testCubicRefinementConvergesWithoutAddingNodes() {
        let original=CubicBezier(start:.init(x:0,y:0),control1:.init(x:25,y:0),
            control2:.init(x:40,y:10),end:.init(x:100,y:160))
        let points=(0...200).map { original.point(at:Double($0)/200) }
        let initial=MatchingCubicFitter.fit(points)
        let refined=MatchingCubicFitter.fit(points,refinementBudget:0.9375)
        XCTAssertGreaterThan(error(initial,points),1)
        XCTAssertLessThan(error(refined,points),0.9375)
        XCTAssertEqual(refined.start,original.start); XCTAssertEqual(refined.end,original.end)
        let constrained=MatchingCubicFitter.fit(points,refinementBudget:0.9375,
            startTangent:.init(dx:1,dy:0),endTangent:-(original.end-original.control2).normalized()!)
        XCTAssertEqual(constrained.control1.y,0)
        XCTAssertLessThan(error(constrained,points),error(initial,points))
        XCTAssertTrue(MatchGeometry.controlled(refined))
    }
    func testFixedRasterRefusalProvidesAttributionAndRawBoundaryIDs() throws {
        let helper=RasterMasterMatchingTests()
        let request=RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),
            reference:helper.box(),images:[try helper.image("round.png",id:"target")],
            options:.init(fitTolerance:1,maxOnCurveNodes:4,maxNodes:4))
        XCTAssertThrowsError(try RasterMasterMatcher.match(request)) { error in
            let d=(error as? MasterMatchError)?.diagnostic
            XCTAssertEqual(d?.code,"fixed-structure-fit"); XCTAssertEqual(d?.stage,"fitting")
            XCTAssertEqual(d?.role,"target"); XCTAssertEqual(d?.existedBeforeFitting,false)
            XCTAssertNotNil(d?.section); XCTAssertNotNil(d?.measuredDeviation)
            XCTAssertEqual(d?.allowedDeviation,0.9375); XCTAssertNotNil(d?.boundarySpan)
            XCTAssertNotNil(d?.locations?.first?.startNode)
            XCTAssertFalse((error as? MasterMatchError)?.isInvalidRequest ?? true)
        }
    }
    func testCoupledHandleSearchPreservesEndpointsAndNodeStructure() {
        let source=CubicBezier(start:.init(x:0,y:0),control1:.init(x:100,y:20),control2:.init(x:280,y:45),end:.init(x:280,y:140))
        let points=(0...256).map { source.point(at:Double($0)/256) }
        let initial=CubicBezier(start:source.start,control1:.init(x:60,y:20),control2:.init(x:280,y:20),end:source.end)
        let coordinate=MatchingCubicFitter.polish(initial,points:points,budget:0.9375,iterations:32)
        let coupled=MatchingCubicFitter.minimax(coordinate,points:points,budget:0.9375)
        XCTAssertGreaterThan(error(coordinate,points),1)
        XCTAssertLessThan(error(coupled,points),0.9375)
        XCTAssertEqual(coupled.start,initial.start);XCTAssertEqual(coupled.end,initial.end)
        XCTAssertTrue(MatchGeometry.controlled(coupled))
    }
    func testVectorLineCanCenterResidualsWithoutAddingHandles() throws {
        let reference=Outline(contours:[.init(nodes:[.init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line),.init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        func target(_ controlX: Double) -> Outline {
            .init(contours:[.init(nodes:[.init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line),.init(x:controlX,y:33,type:.offcurve),.init(x:controlX,y:67,type:.offcurve),.init(x:100,y:100,type:.curve),.init(x:0,y:100,type:.line)])])
        }
        let request=MasterMatchRequest(axis:.init(tag:"wght",locations:[400,700]),reference:.init(id:"regular",outline:reference),target:.init(id:"bold",outline:target(102.2)),options:.init(fitTolerance:1,maxOnCurveNodes:4,maxNodes:4))
        let result=try OutlineMatcher.match(request)
        XCTAssertEqual(result.reference.outline,reference)
        XCTAssertEqual(result.target.outline.contours[0].nodes.map(\.type),[.line,.line,.line,.line])
        XCTAssertLessThanOrEqual(try PairGeometry.measure(request.target.outline,result.target.outline,tolerance:1).upperBound,1)
        XCTAssertEqual(result.nodeBudget?.totalNodes,4)
        var impossible=request;impossible.target.outline=target(104)
        XCTAssertThrowsError(try OutlineMatcher.match(impossible))
    }
}
