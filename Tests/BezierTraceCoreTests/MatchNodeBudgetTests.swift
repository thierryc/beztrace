// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import CryptoKit
import XCTest
@testable import BezierTraceCore

final class MatchNodeBudgetTests: XCTestCase {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/matching/budget-v1")
    func testFrozenBudgetCases() throws {
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as? [String:Any])
        for item in try XCTUnwrap(manifest["fixtures"] as? [[String:String]]) {
            let data=try Data(contentsOf:root.appendingPathComponent(item["file"]!))
            XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),item["sha256"])
            let request=try JSONDecoder().decode(MasterMatchRequest.self,from:data)
            if item["outcome"]=="budget" {
                XCTAssertThrowsError(try OutlineMatcher.match(request)) { error in
                    guard case MasterMatchError.nodeBudget = error else { return XCTFail("wrong error: \(error)") }
                }
            } else {
                let result=try OutlineMatcher.match(request)
                let budget=try XCTUnwrap(result.nodeBudget)
                XCTAssertLessThanOrEqual(budget.addedOnCurves!,request.options.maxAdditionalOnCurveNodes)
                XCTAssertLessThanOrEqual(budget.resultOnCurves,request.options.maxOnCurveNodes)
                if item["file"]=="redundant-zero-budget.json" {
                    XCTAssertEqual(budget.resultOnCurves,4)
                    XCTAssertEqual(result.reference.outline,request.reference.outline)
                }
            }
        }
    }
    func testBudgetsAreGlobalAndInvalidValuesAreRejected() throws {
        let data=try Data(contentsOf:root.appendingPathComponent("shared-explicit-budget.json"))
        var request=try JSONDecoder().decode(MasterMatchRequest.self,from:data)
        request.options.maxOnCurveNodes=3
        XCTAssertThrowsError(try OutlineMatcher.match(request))
        request.options.maxOnCurveNodes=64; request.options.maxAdditionalOnCurveNodes = -1
        XCTAssertThrowsError(try OutlineMatcher.match(request))
        request.options.maxAdditionalOnCurveNodes=1
        for role in [true,false] {
            var extra=role ? request.reference.outline.contours[0] : request.target.outline.contours[0]
            for i in extra.nodes.indices { extra.nodes[i].x += 300 }
            if role { request.reference.outline.contours.append(extra) }
            else { request.target.outline.contours.append(extra) }
        }
        request.options.contourPairs=[0,1]
        XCTAssertThrowsError(try OutlineMatcher.match(request)) { error in
            guard case MasterMatchError.nodeBudget = error else { return XCTFail("budget must cover the whole glyph: \(error)") }
        }
    }
    func testDefaultBudgetSurvivesDecodingAndFreeFitDoesNotInsertPoints() throws {
        let empty=try JSONDecoder().decode(MasterMatchOptions.self,from:Data("{}".utf8))
        XCTAssertEqual(empty.maxAdditionalOnCurveNodes,0); XCTAssertEqual(empty.maxOnCurveNodes,64)
        let curve=CubicBezier(start:.init(x:0,y:0),control1:.init(x:15,y:75),control2:.init(x:90,y:80),end:.init(x:100,y:0))
        let points=(0...100).map { curve.point(at:Double($0)/100) }
        let fit=MatchingCubicFitter.fit(points)
        XCTAssertEqual(fit.start,curve.start); XCTAssertEqual(fit.end,curve.end)
        let polygon=(0...200).map { fit.point(at:Double($0)/200) }
        XCTAssertLessThan(points.map { MatchGeometry.distance($0,to:polygon) }.max()!,0.5)
        XCTAssertTrue(MatchGeometry.controlled(fit))
    }
    func testHandleAdditionAlsoObeysTotalNodeCeiling() throws {
        let square=Outline(contours:[Contour(nodes:[Node(x:0,y:0,type:.line),Node(x:100,y:0,type:.line),Node(x:100,y:100,type:.line),Node(x:0,y:100,type:.line)])])
        let points:[(Double,Double,NodeKind)]=[(0,50,.curve),(0,22.385,.offcurve),(22.385,0,.offcurve),
            (50,0,.curve),(77.615,0,.offcurve),(100,22.385,.offcurve),(100,50,.curve),
            (100,77.615,.offcurve),(77.615,100,.offcurve),(50,100,.curve),(22.385,100,.offcurve),(0,77.615,.offcurve)]
        let circle=Outline(contours:[Contour(nodes:points.map { Node(x:$0.0,y:$0.1,type:$0.2,smooth:$0.2 != .offcurve) })])
        var request=MasterMatchRequest(axis:.init(tag:"wght",locations:[0,1]),reference:.init(id:"a",outline:square),target:.init(id:"b",outline:circle),
            options:.init(referencePolicy:.sharedSubdivision,startNodes:[0],maxNodes:8))
        XCTAssertThrowsError(try OutlineMatcher.match(request)) { error in
            guard case MasterMatchError.nodeBudget = error else { return XCTFail("handles must count: \(error)") }
        }
        request.options.maxNodes=12
        let result=try OutlineMatcher.match(request)
        XCTAssertEqual(result.nodeBudget?.addedOnCurves,0)
        XCTAssertEqual(result.nodeBudget?.totalNodes,12)
    }
}
