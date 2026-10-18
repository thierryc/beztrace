// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class HybridCubicFitterTests: XCTestCase {
    let cubic=CubicBezier(start:.init(x:0,y:0),control1:.init(x:18,y:52),control2:.init(x:77,y:37),end:.init(x:100,y:0))
    func testBoundedPolynomialIsolationIncludingRepeatedRoots() {
        let p=FitPolynomial.multiply(FitPolynomial.multiply([-0.2,1],[-0.2,1]),FitPolynomial.multiply([-0.7,1],[-0.9,1]))
        let roots=FitPolynomial.roots(p,in:0...1)
        XCTAssertEqual(roots.count,3)
        for (actual,expected) in zip(roots,[0.2,0.7,0.9]) { XCTAssertEqual(actual,expected,accuracy:1e-7) }
        XCTAssertEqual(FitPolynomial.roots([0,0,0],in:0...1),[])
        XCTAssertEqual(FitPolynomial.roots([Double.nan,1],in:0...1),[])
        XCTAssertEqual(FitPolynomial.roots([-2,1],in:0...1),[])
    }
    func testMomentsAndRecoveryFromExactSubdivision() throws {
        let (a,b)=cubic.split(at:0.37)
        let original=LevienCubicFitter.moments([cubic]),split=LevienCubicFitter.moments([a,b])
        XCTAssertEqual(original.area,split.area,accuracy:1e-9)
        XCTAssertEqual(original.first,split.first,accuracy:1e-7)
        let result=try XCTUnwrap(HybridCubicFitter.fit([a,b],tolerance:0.1))
        XCTAssertEqual(result.method,.levien)
        XCTAssertLessThan(result.curve.control1.matchDistance(to:cubic.control1),1e-6)
        XCTAssertLessThan(result.curve.control2.matchDistance(to:cubic.control2),1e-6)
        XCTAssertTrue(result.report.accepted)
        XCTAssertEqual(result.curve,HybridCubicFitter.fit([a,b],tolerance:0.1)?.curve)
    }
    func testTransformsPreserveRecovery() throws {
        for scale in [0.1,1.0,10.0] {
            func transform(_ p: Point2D) -> Point2D { .init(x:300-p.y*scale,y:-70-p.x*scale) }
            let c=CubicBezier(start:transform(cubic.start),control1:transform(cubic.control1),control2:transform(cubic.control2),end:transform(cubic.end))
            let (a,b)=c.split(at:0.5)
            let result=try XCTUnwrap(HybridCubicFitter.fit([a,b],tolerance:0.01*scale))
            XCTAssertEqual(result.method,.levien)
            XCTAssertLessThan(result.curve.control1.matchDistance(to:c.control1),1e-5)
            XCTAssertLessThan(result.curve.control2.matchDistance(to:c.control2),1e-5)
        }
    }
    func testStraightDegenerateMomentsUseVerifiedFallback() throws {
        let a=lineCubic(from:.init(x:0,y:0),to:.init(x:50,y:0))
        let b=lineCubic(from:a.end,to:.init(x:100,y:0))
        let result=try XCTUnwrap(HybridCubicFitter.fit([a,b],tolerance:0.1))
        XCTAssertEqual(result.method,.refinedLeastSquares)
        XCTAssertTrue(result.report.accepted)
        XCTAssertNil(HybridCubicFitter.fit([],tolerance:1))
        XCTAssertNil(HybridCubicFitter.fit([cubic],tolerance:Double.nan))
    }
    func testMovedEndpointsAreMeasuredAgainstOriginalBoundary() {
        let source=[Point2D(x:0,y:0),Point2D(x:50,y:0),Point2D(x:100,y:0)]
        XCTAssertNil(HybridCubicFitter.fit(polyline:source,tolerance:1,start:.init(x:0,y:3),end:.init(x:100,y:3),
            startTangent:.init(dx:1,dy:0),endTangent:.init(dx:1,dy:0)))
        XCTAssertEqual(source[0].y,0)
    }
    func testRasterRefinedEUsesLeastSquaresWhenMomentCandidatesFail() throws {
        // The two original spans responsible for the benchmark's extra e merge.
        let coordinates:[[Double]]=[
            [302.89296283932873,320.2950308568406,359.24672584526263,320.2950308568406,413.6142774044146,339.7605635752409,443.82496166590244,383.0977091715112],
            [443.82496166590244,383.0977091715112,451.7303867752024,394.43802030107025,462.3644949502989,421.84725546288485,472.36346877288724,428.73706693251376]]
        let curves=coordinates.map { c in CubicBezier(start:.init(x:c[0],y:c[1]),control1:.init(x:c[2],y:c[3]),control2:.init(x:c[4],y:c[5]),end:.init(x:c[6],y:c[7])) }
        let result=try XCTUnwrap(HybridCubicFitter.fit(curves,tolerance:1))
        XCTAssertEqual(result.method,.refinedLeastSquares)
        XCTAssertLessThanOrEqual(result.report.deviation.upperBound,1)
        XCTAssertEqual(result.curve.start,curves[0].start)
        XCTAssertEqual(result.curve.end,curves[1].end)
    }
    func testExactSourceIntervalPieces() throws {
        let (a,b)=cubic.split(at:0.5)
        let ring=MatchRing(spans:[a,b].map { .init(curve:$0,line:false,startSource:nil,controlSources:[nil,nil],smooth:true) })
        let pieces=ring.sourceCurves(0.1,0.9)
        XCTAssertEqual(pieces.count,2)
        XCTAssertLessThan(pieces[0].start.matchDistance(to:ring.point(0.1)),1e-7)
        XCTAssertLessThan(pieces[1].end.matchDistance(to:ring.point(0.9)),1e-7)
        XCTAssertEqual(pieces[0].end,pieces[1].start)
    }
}
