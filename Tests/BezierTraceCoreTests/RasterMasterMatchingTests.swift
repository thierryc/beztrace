// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import CryptoKit
import Foundation
import XCTest
@testable import BezierTraceCore

final class RasterMasterMatchingTests: XCTestCase {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/matching/raster-v1")
    func image(_ name: String, id: String, transform: [Double]? = nil) throws -> MatchRasterInput {
        .init(id:id,imageData:try Data(contentsOf:root.appendingPathComponent(name)),
              transform:transform ?? [128.0/1088,0,0,128.0/1088,0,0])
    }
    func box() -> MatchMaster {
        .init(id:"reference",outline:.init(contours:[.init(nodes:[
            .init(x:31.5,y:31.5,type:.line),.init(x:95.5,y:31.5,type:.line),
            .init(x:95.5,y:95.5,type:.line),.init(x:31.5,y:95.5,type:.line)])]))
    }
    func testFrozenRasterCorpus() throws {
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as? [String:Any])
        for item in try XCTUnwrap(value["files"] as? [[String:String]]) {
            let data = try Data(contentsOf:root.appendingPathComponent(item["path"]!))
            XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),item["sha256"])
        }
    }
    func testReferenceGuidedPlacementAndTolerance() throws {
        let request = RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[100,900]),
            reference:box(),images:[try image("wide-rectangle.png",id:"target")],options:.init(fitTolerance:1))
        let result = try RasterMasterMatcher.match(request)
        XCTAssertEqual(result.reference.outline,box().outline)
        XCTAssertEqual(result.reference.outline.contours[0].nodes.count,result.target.outline.contours[0].nodes.count)
        XCTAssertLessThanOrEqual(result.rasterSources![0].maximumBoundaryDeviation,1)
        XCTAssertEqual(result.rasterSources![0].sourceWidth,128)
        let xs = result.target.outline.contours[0].nodes.map(\.x)
        XCTAssertEqual(xs.min()!,23.5,accuracy:1.01); XCTAssertEqual(xs.max()!,103.5,accuracy:1.01)
        var strict = request; strict.options.fitTolerance = 0.00001
        XCTAssertThrowsError(try RasterMasterMatcher.match(strict))
    }
    func testJointDifferentMastersAndReferenceSharedSubdivision() throws {
        let joint = RasterMasterMatchRequest(mode:.traceBoth,axis:.init(tag:"wght",locations:[0,1]),
            images:[try image("rectangle.png",id:"a"),try image("wide-rectangle.png",id:"b")],
            options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1))
        let result = try RasterMasterMatcher.match(joint)
        XCTAssertNotEqual(result.reference.outline,result.target.outline)
        XCTAssertTrue(result.rasterSources!.allSatisfy { $0.maximumBoundaryDeviation <= 1 })
        let guide = RasterMasterMatchRequest(mode:.traceToReference,axis:joint.axis,reference:box(),
            images:[try image("round.png",id:"b")],options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1))
        let guided = try RasterMasterMatcher.match(guide)
        XCTAssertLessThan(MatchGeometry.deviation(try MatchRing(box().outline.contours[0]),
            try MatchRing(guided.reference.outline.contours[0]),tolerance:1e-4),1e-4)
        XCTAssertLessThanOrEqual(guided.rasterSources![0].maximumBoundaryDeviation,1)
    }
    func testJointPlanningCountersTerminalsAndAffine() throws {
        for name in ["rectangle.png","round.png","counter.png","terminal.png"] {
            let transform = [0.15,0.02,-0.01,0.12,17.0,-8.0]
            let request = RasterMasterMatchRequest(mode:.traceBoth,axis:.init(tag:"wght",locations:[900,100]),
                images:[try image(name,id:"a",transform:transform),try image(name,id:"b",transform:transform)],
                options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1))
            let result = try RasterMasterMatcher.match(request)
            XCTAssertEqual(result.reference.outline,result.target.outline)
            XCTAssertEqual(result.reference.outline.contours.count,name == "counter.png" ? 2 : 1)
            if name == "counter.png" {
                let areas = try result.reference.outline.contours.map { try MatchRing($0).area }
                XCTAssertLessThan(areas[0]*areas[1],0,"Counters must remain holes with nonzero fill")
            }
            XCTAssertTrue(result.rasterSources!.allSatisfy { $0.maximumBoundaryDeviation <= 1 && $0.transform == transform })
            XCTAssertEqual(try MasterMatchSerializer.json(result),try MasterMatchSerializer.json(RasterMasterMatcher.match(request)))
        }
    }
    func testTopologyModesAndInvalidImagesFail() throws {
        var request = RasterMasterMatchRequest(mode:.traceBoth,axis:.init(tag:"wght",locations:[0,1]),
            images:[try image("rectangle.png",id:"a"),try image("counter.png",id:"b")],
            options:.init(referencePolicy:.sharedSubdivision))
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
        request.images[1] = try image("rectangle.png",id:"b"); request.images[1].transform = [0,0,0,0,0,0]
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
        request.images[1].transform = [1,0,0,1,0,0]; request.images[1].imageData = Data([0,1])
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
        request.options.referencePolicy = .fixed
        XCTAssertThrowsError(try RasterMasterMatcher.match(request))
    }
    func testPixelTangentsDoNotReplaceCurveTangents() throws {
        let corpus = root.deletingLastPathComponent().appendingPathComponent("raster-v2")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:corpus.appendingPathComponent("manifest.json"))) as? [String:Any])
        let item = try XCTUnwrap((manifest["files"] as? [[String:String]])?.first)
        let data = try Data(contentsOf:corpus.appendingPathComponent(item["path"]!))
        XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),item["sha256"])
        let a = MatchRasterInput(id:"a",imageData:data,transform:[1024.0/1088,0,0,1024.0/1088,0,0])
        let b = MatchRasterInput(id:"b",imageData:data,transform:a.transform)
        let result = try RasterMasterMatcher.match(.init(mode:.traceBoth,axis:.init(tag:"wght",locations:[0,1]),
            images:[a,b],options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1)))
        XCTAssertEqual(result.reference.outline,result.target.outline)
        XCTAssertLessThanOrEqual(result.reference.outline.contours[0].nodes.count,40)
        XCTAssertLessThanOrEqual(result.rasterSources![0].maximumBoundaryDeviation,0.6,
            "Pixel-scale edge directions must not degrade a smooth antialiased ellipse")
    }
    func testSharedRasterSubdivisionRetainsCloseReferenceKnots() throws {
        var reference = box()
        reference.outline.contours[0].nodes.insert(.init(x:31.50001,y:31.5,type:.line),at:1)
        let request = RasterMasterMatchRequest(mode:.traceToReference,axis:.init(tag:"wght",locations:[0,1]),
            reference:reference,images:[try image("wide-rectangle.png",id:"target")],
            options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1))
        let result = try RasterMasterMatcher.match(request)
        let mapping = result.contours[0].referenceSourceNodes.compactMap { $0 }
        XCTAssertEqual(Set(mapping),Set(reference.outline.contours[0].nodes.indices))
        for index in reference.outline.contours[0].nodes.indices {
            let output = try XCTUnwrap(result.contours[0].referenceSourceNodes.firstIndex(of:index))
            XCTAssertEqual(result.reference.outline.contours[0].nodes[output].x,reference.outline.contours[0].nodes[index].x)
            XCTAssertEqual(result.reference.outline.contours[0].nodes[output].y,reference.outline.contours[0].nodes[index].y)
        }
    }
}
