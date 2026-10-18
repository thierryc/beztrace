// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class JointMasterSmootherTests: XCTestCase {
    func ellipse(_ rx: Double,_ ry: Double,_ shear: Double = 0) -> Outline {
        let k=0.5522847498307936
        let values:[[Double]]=[[rx,0,rx,k*ry,k*rx,ry,0,ry],[0,ry,-k*rx,ry,-rx,k*ry,-rx,0],
            [-rx,0,-rx,-k*ry,-k*rx,-ry,0,-ry],[0,-ry,k*rx,-ry,rx,-k*ry,rx,0]]
        func p(_ x: Double,_ y: Double) -> Point2D { .init(x:x+shear*y+350,y:y+400) }
        return Outline(contours:[MatchRing(spans:values.map { c in
            .init(curve:.init(start:p(c[0],c[1]),control1:p(c[2],c[3]),control2:p(c[4],c[5]),end:p(c[6],c[7])),
                line:false,startSource:nil,controlSources:[nil,nil],smooth:true)
        }).serialized().0])
    }
    func pair(_ amount: Double) -> (Outline,Outline) {
        let a=ellipse(220,300),base=ellipse(270,320,0.35)
        var b=base
        let n=b.contours[0].nodes.count,p=b.contours[0].nodes[0].point
        for (i,scale) in [(n-1,1-amount),(1,1+amount)] {
            let q=p+(base.contours[0].nodes[i].point-p)*scale
            b.contours[0].nodes[i].x=q.x;b.contours[0].nodes[i].y=q.y
        }
        return (a,b)
    }
    func run(_ a: Outline,_ b: Outline,tolerance: Double = 1,source: Outline? = nil) throws -> JointSmoothingResult {
        try JointMasterSmoother.smooth(.init(reference:a,target:b,sourceTarget:source ?? b,fitTolerance:tolerance))
    }
    func assertPreserved(_ a: Outline,_ b: Outline,_ result: JointSmoothingResult,file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(a,result.reference,file:file,line:line)
        for (before,after) in zip(b.contours,result.target.contours) {
            XCTAssertEqual(before.nodes.map(\.type),after.nodes.map(\.type),file:file,line:line)
            XCTAssertEqual(before.nodes.map(\.smooth),after.nodes.map(\.smooth),file:file,line:line)
            for (p,q) in zip(before.nodes,after.nodes) where p.type != .offcurve { XCTAssertEqual(p,q,file:file,line:line) }
        }
    }
    func testMildRepairKeepsReferenceAndStructureAndEliminatesIntermediateKink() throws {
        let (a,b)=pair(0.015),r=try run(a,b)
        XCTAssertEqual(r.report.status,.smoothed)
        XCTAssertEqual(r.report.changedHandles.count,2)
        XCTAssertGreaterThan(r.report.beforeMaximumTangencyResidual!,0.1)
        XCTAssertEqual(r.report.beforeMaximumTangencyResidual,
            try InterpolationValidator.validate(reference:a,target:b,intervals:200).maximumTangencyResidual)
        XCTAssertLessThan(r.report.afterMaximumTangencyResidual!,1e-8)
        XCTAssertLessThanOrEqual(r.report.proposalDeviation!.upperBound,1)
        assertPreserved(a,b,r)
        // Check factors different from the engine's fixed sample grid too.
        for factor in [0.12345,0.3333333,0.73929] {
            let o=try InterpolationValidator.interpolate(reference:a,target:r.target,factor:factor)
            let nodes=o.contours[0].nodes,p=nodes[0].point
            XCTAssertLessThan(abs((p-nodes.last!.point).cross(nodes[1].point-p)),1e-7)
        }
    }
    func testStrongRepairRefusesAtomicallyAtOriginalBudget() throws {
        let (a,b)=pair(0.35),r=try run(a,b)
        XCTAssertEqual(r.report.status,.refused)
        XCTAssertEqual(r.target,b);XCTAssertEqual(r.reference,a)
        XCTAssertTrue(r.report.changedHandles.isEmpty)
        XCTAssertEqual(r.report.proposedHandleChanges,2)
        XCTAssertGreaterThan(r.report.proposalDeviation!.lowerBound,10)
    }
    func testOneBudgetAndIdempotence() throws {
        let (a,b)=pair(0.015)
        XCTAssertEqual(try run(a,b,tolerance:0.5).report.status,.refused)
        let r=try run(a,b),again=try run(a,r.target,source:b)
        XCTAssertEqual(again.report.status,.unchanged);XCTAssertEqual(again.target,r.target)
        var displaced=b
        for i in displaced.contours[0].nodes.indices { displaced.contours[0].nodes[i].y+=3 }
        let failed=try run(a,r.target,source:displaced)
        XCTAssertEqual(failed.report.status,.refused);XCTAssertEqual(failed.target,r.target)
    }
    func testCornersAndUnmarkedJoinsStayFixed() throws {
        var (a,b)=pair(0.015)
        a.contours[0].nodes[0].smooth=false
        b.contours[0].nodes[0].smooth=false
        let r=try run(a,b)
        XCTAssertEqual(r.report.status,.unchanged);XCTAssertEqual(r.target,b)
    }
    func testNonCollinearReferenceIsNotRepaired() throws {
        var (a,b)=pair(0.015)
        a.contours[0].nodes[1].x+=1
        let r=try run(a,b)
        XCTAssertEqual(r.report.status,.refused);XCTAssertEqual(r.reference,a);XCTAssertEqual(r.target,b)
    }
    func testLineCurveAndCurveLineKeepAllOnCurves() throws {
        let a=Outline(contours:[Contour(nodes:[
            .init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line,smooth:true),
            .init(x:130,y:0,type:.offcurve),.init(x:150,y:30,type:.offcurve),
            .init(x:150,y:50,type:.curve,smooth:true),.init(x:150,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a;b.contours[0].nodes[2].x+=5;b.contours[0].nodes[3].y-=5
        let r=try run(a,b,tolerance:5)
        XCTAssertEqual(r.report.status,.smoothed);XCTAssertEqual(r.report.changedHandles.count,2)
        assertPreserved(a,b,r)
    }
    func testTwoLineJoinCannotMoveProtectedOnCurves() throws {
        let a=Outline(contours:[Contour(nodes:[.init(x:0,y:0,type:.line),.init(x:50,y:0,type:.line,smooth:true),
            .init(x:100,y:0,type:.line),.init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a;b.contours[0].nodes[1].x=30;b.contours[0].nodes[1].y=15;b.contours[0].nodes[2].y=50
        let r=try run(a,b)
        XCTAssertEqual(r.report.status,.refused);XCTAssertEqual(r.target,b)
    }
    func testAdjacentJoinsCannotEachSpendTheFullSourceBudget() throws {
        let a=Outline(contours:[Contour(nodes:[
            .init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line,smooth:true),
            .init(x:130,y:0,type:.offcurve),.init(x:150,y:30,type:.offcurve),
            .init(x:150,y:50,type:.curve,smooth:true),.init(x:150,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a;b.contours[0].nodes[2].x+=5;b.contours[0].nodes[3].y-=5
        var firstOnly=b,secondOnly=b
        firstOnly.contours[0].nodes[2]=a.contours[0].nodes[2]
        secondOnly.contours[0].nodes[3]=a.contours[0].nodes[3]
        XCTAssertLessThan(try PairGeometry.measure(b,firstOnly,tolerance:2.5).upperBound,2.5)
        XCTAssertLessThan(try PairGeometry.measure(b,secondOnly,tolerance:2.5).upperBound,2.5)
        let result=try run(a,b,tolerance:2.5)
        XCTAssertEqual(result.report.status,.refused)
        XCTAssertGreaterThan(result.report.proposalDeviation!.lowerBound,2.5)
        XCTAssertEqual(result.target,b)
    }
    func testAnalyticCollapseBetweenInterpolationSamplesIsRefused() throws {
        let a=ellipse(100,150)
        var b=a
        for i in b.contours[0].nodes.indices {
            b.contours[0].nodes[i].x = -2*a.contours[0].nodes[i].x+1000
            b.contours[0].nodes[i].y = -2*a.contours[0].nodes[i].y+1200
        }
        let r=try run(a,b,tolerance:100)
        XCTAssertEqual(r.report.status,.refused);XCTAssertEqual(r.target,b)
        XCTAssertTrue(r.report.reason?.contains("collapse between masters")==true)
    }
    func testUnchangedTargetStillRequiresCompleteInterpolationCheck() throws {
        let a=Outline(contours:[Contour(nodes:[.init(x:0,y:0,type:.line),.init(x:100,y:0,type:.line),
            .init(x:100,y:100,type:.line),.init(x:0,y:100,type:.line)])])
        var b=a
        for i in b.contours[0].nodes.indices {
            b.contours[0].nodes[i].x=100-a.contours[0].nodes[i].x
            b.contours[0].nodes[i].y=100-a.contours[0].nodes[i].y
        }
        // Endpoints are valid and no handles move, but the midpoint collapses.
        let r=try run(a,b)
        XCTAssertEqual(r.report.status,.refused)
        XCTAssertEqual(r.report.proposedHandleChanges,0)
        XCTAssertEqual(r.report.proposalDeviation?.upperBound,0)
        XCTAssertTrue(r.report.reason?.contains("regular smooth interpolation")==true)
        XCTAssertEqual(r.target,b);XCTAssertEqual(r.reference,a)
    }
    func testPrefixWrapAndAffineCovariance() throws {
        let (a,b)=pair(0.015),expected=try run(a,b)
        func transformed(_ o: Outline) -> Outline {
            var result=o
            for i in result.contours[0].nodes.indices {
                let p=o.contours[0].nodes[i]
                result.contours[0].nodes[i].x=200-p.y*2;result.contours[0].nodes[i].y=100+p.x*2
            }
            result.contours[0].nodes=Array(result.contours[0].nodes.dropFirst())+[result.contours[0].nodes[0]]
            return result
        }
        let ta=transformed(a),tb=transformed(b),result=try run(ta,tb,tolerance:2)
        XCTAssertEqual(result.report.status,.smoothed)
        assertPreserved(ta,tb,result)
        for (p,q) in zip(result.target.contours[0].nodes,transformed(expected.target).contours[0].nodes) {
            XCTAssertEqual(p.x,q.x,accuracy:1e-8);XCTAssertEqual(p.y,q.y,accuracy:1e-8)
        }
    }
    func testInvalidLimitsAndIncompatibleNodesThrow() throws {
        let (a,b)=pair(0.015)
        XCTAssertThrowsError(try run(a,b,tolerance:Double.nan))
        var c=b;c.contours[0].nodes[1].type = .line
        XCTAssertThrowsError(try run(a,c))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        XCTAssertEqual(try encoder.encode(run(a,b)),try encoder.encode(run(a,b)))
    }
}
