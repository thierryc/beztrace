// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import CryptoKit
import Foundation
import XCTest
@testable import BezierTraceCore

final class MatchCorrespondenceTests: XCTestCase {
    private let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/matching/correspondence-v1")
    private struct Fixture: Decodable { var reference: Contour; var target: Contour }
    private func fixture() throws -> (MatchRing,MatchRing) {
        let data=try Data(contentsOf:root.appendingPathComponent("serpentine.json"))
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as! [String:Any]
        let record=(manifest["files"] as! [[String:String]])[0]
        XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),record["sha256"])
        let input=try JSONDecoder().decode(Fixture.self,from:data)
        return try (MatchRing(input.reference),MatchRing(input.target))
    }
    func testThickSerpentineKeepsShapeLocationsAndStrictOrder() throws {
        let (a,b)=try fixture(), map=OutlineMatcher.anchors(a,b)
        XCTAssertEqual(map.first!.0,0); XCTAssertEqual(map.first!.1,0)
        XCTAssertEqual(map.last!.0,1); XCTAssertEqual(map.last!.1,1)
        for (x,y) in zip(map,map.dropFirst()) { XCTAssertLessThan(x.0,y.0); XCTAssertLessThan(x.1,y.1) }
        for i in 0...128 {
            let f=Double(i)/128, t=OutlineMatcher.warp(f,map)
            XCTAssertLessThan(OutlineMatcher.normalized(a.point(f),a.bounds).distance(to:
                OutlineMatcher.normalized(b.point(t),b.bounds)),0.19)
            XCTAssertEqual(OutlineMatcher.warp(t,map,inverse:true),f,accuracy:1e-9)
        }
        XCTAssertEqual(a.spans.count,130); XCTAssertEqual(b.spans.count,130)
    }
    func testUnrelatedFeatureCannotDragShapeCorrespondence() throws {
        var (a,b)=try fixture()
        for i in a.spans.indices { a.spans[i].featureRole=0; b.spans[i].featureRole=0 }
        a.spans[35].featureRole=1; b.spans[100].featureRole=1
        let f=a.fractions()[35], map=OutlineMatcher.anchors(a,b), t=OutlineMatcher.warp(f,map)
        XCTAssertGreaterThan(abs(t-b.fractions()[100]),0.2)
        XCTAssertLessThan(OutlineMatcher.normalized(a.point(f),a.bounds).distance(to:
            OutlineMatcher.normalized(b.point(t),b.bounds)),0.19)
    }
    func testCyclicStartUsesWholeShapeDespiteDifferentLabels() throws {
        let (a,source)=try fixture()
        for shift in [0,23,71] {
            var b=source.rotated(shift)
            for i in b.spans.indices { b.spans[i].featureRole=5 }
            let start=try OutlineMatcher.startingPoint(a,b,referenceBounds:a.bounds,targetBounds:b.bounds,override:-1,contour:0)
            let chosen=b.rotated(start)
            XCTAssertLessThan(OutlineMatcher.normalized(a.spans[0].curve.start,a.bounds).distance(to:
                OutlineMatcher.normalized(chosen.spans[0].curve.start,b.bounds)),0.12)
            XCTAssertEqual(chosen.spans[0].startSource,source.spans[0].startSource)
        }
        let b=source.rotated(23)
        let forced=try OutlineMatcher.startingPoint(a,b,referenceBounds:a.bounds,targetBounds:b.bounds,
            override:b.spans[10].startSource!,contour:0)
        XCTAssertEqual(forced,10)
    }
    func testIdenticalShapeMapIsIdentity() throws {
        let (a,_)=try fixture(),map=OutlineMatcher.anchors(a,a)
        for i in 0...100 { let f=Double(i)/100; XCTAssertEqual(OutlineMatcher.warp(f,map),f,accuracy:1e-12) }
    }
}
