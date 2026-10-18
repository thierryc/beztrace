// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class SourceGeometryVerifierTests: XCTestCase {
    func testAnalyticDistanceEnclosedInBothDirections() throws {
        let a=[Point2D(x:0,y:0),Point2D(x:10,y:0)]
        let b=[Point2D(x:0,y:0),Point2D(x:5,y:2),Point2D(x:10,y:0)]
        for (source,target) in [(a,b),(b,a)] {
            let m=try SourceGeometryVerifier.measure(source,target,tolerance:0.1,flattenAllowance:0)
            XCTAssertLessThanOrEqual(m.lowerBound,2)
            XCTAssertGreaterThanOrEqual(m.upperBound,2)
            XCTAssertLessThan(m.uncertainty,0.003)
        }
    }
    func testCubicBulgeCannotPassOnEndpointsAlone() throws {
        let a=Point2D(x:0,y:0),b=Point2D(x:10,y:0)
        let c=CubicBezier(start:a,control1:.init(x:0,y:6),control2:.init(x:10,y:6),end:b)
        let source=try SourceGeometryVerifier.prepare(polyline:[a,b],tolerance:1)
        let report=try SourceGeometryVerifier.verify(c,source:source,tolerance:1,start:a,end:b,startTangent:nil,endTangent:nil)
        XCTAssertFalse(report.accepted)
        XCTAssertGreaterThan(report.deviation.lowerBound,4.48)
        XCTAssertGreaterThanOrEqual(report.deviation.upperBound,4.5)
    }
    func testInvalidAndExhaustedEvidenceRefuses() throws {
        let a=[Point2D(x:0,y:0),Point2D(x:10,y:0)]
        for tolerance in [0,-1,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try SourceGeometryVerifier.measure(a,a,tolerance:tolerance,flattenAllowance:0))
            XCTAssertThrowsError(try SourceGeometryVerifier.prepare(polyline:a,tolerance:tolerance))
        }
        XCTAssertThrowsError(try SourceGeometryVerifier.measure([],a,tolerance:1,flattenAllowance:0))
        XCTAssertThrowsError(try SourceGeometryVerifier.measure(a,a,tolerance:1e-12,flattenAllowance:0))
        XCTAssertThrowsError(try SourceGeometryVerifier.prepare(polyline:[a[0],.init(x:Double.nan,y:0)],tolerance:1))
        let c=lineCubic(from:a[0],to:a[1]),d=lineCubic(from:.init(x:20,y:0),to:.init(x:30,y:0))
        XCTAssertThrowsError(try SourceGeometryVerifier.prepare([c,d],tolerance:1))
        let gap=lineCubic(from:.init(x:10+1e-9,y:0),to:.init(x:20,y:0))
        XCTAssertThrowsError(try SourceGeometryVerifier.prepare([c,gap],tolerance:1))
    }
    func testDirectedTangentsAndEndpointProtection() throws {
        let a=Point2D(x:0,y:0),b=Point2D(x:10,y:0)
        let source=try SourceGeometryVerifier.prepare(polyline:[a,b],tolerance:1)
        let c=lineCubic(from:a,to:b)
        XCTAssertThrowsError(try SourceGeometryVerifier.verify(c,source:source,tolerance:1,start:a,end:b,
            startTangent:.init(dx:-1,dy:0),endTangent:nil))
        XCTAssertThrowsError(try SourceGeometryVerifier.verify(c,source:source,tolerance:1,start:.init(x:0,y:0.1),end:b,
            startTangent:nil,endTangent:nil))
    }
    func testNewInflectionRefusedEvenInsideDistanceBudget() throws {
        let a=Point2D(x:0,y:0),b=Point2D(x:10,y:0)
        let source=try SourceGeometryVerifier.prepare(polyline:[a,b],tolerance:1)
        let c=CubicBezier(start:a,control1:.init(x:3,y:0.2),control2:.init(x:7,y:-0.2),end:b)
        let report=try SourceGeometryVerifier.verify(c,source:source,tolerance:1,start:a,end:b,startTangent:nil,endTangent:nil)
        XCTAssertLessThan(report.deviation.upperBound,1)
        XCTAssertFalse(report.accepted)
    }
}
