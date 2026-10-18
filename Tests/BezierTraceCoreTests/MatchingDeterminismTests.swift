// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import XCTest
@testable import BezierTraceCore

final class MatchingDeterminismTests: XCTestCase {
    func testNormHasArchitectureIndependentIEEEValues() {
        XCTAssertEqual(MatchMath.length(0.3551587301586778,-0.09198931073922267),0.36687839524589316)
        XCTAssertEqual(MatchMath.length(0.1814822082678802,-0.09491310892178717),0.2048030521329828)
        XCTAssertEqual(MatchMath.length(0,0),0)
        XCTAssertEqual(MatchMath.length(3e200,4e200)/1e200,5,accuracy:1e-14)
        XCTAssertEqual(MatchMath.length(3e-200,4e-200)/1e-200,5,accuracy:1e-14)
    }
    func testPrivateRStageEvidence() throws {
        guard let source=ProcessInfo.processInfo.environment["BEZTRACE_PRIVATE_R"],let destination=ProcessInfo.processInfo.environment["BEZTRACE_STAGE_EVIDENCE"] else { return }
        let root=URL(fileURLWithPath:source),out=URL(fileURLWithPath:destination)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let outline=try JSONDecoder().decode(Outline.self,from:Data(contentsOf:root.appendingPathComponent("R-regular.outline.json")))
        let image=MatchRasterInput(id:"bold",imageData:try Data(contentsOf:root.appendingPathComponent("R-bold-proposal.png")),transform:try JSONDecoder().decode([Double].self,from:Data(contentsOf:root.appendingPathComponent("R-proposal-transform.json"))))
        let count=outline.contours.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count },total=outline.contours.reduce(0) { $0+$1.nodes.count }
        var evidence:[RasterMasterMatcher.FitEvidence]=[]
        do {
            let r=try RasterMasterMatcher.match(.init(mode:.traceToReference,axis:.init(tag:"wght",locations:[400,700]),reference:.init(id:"regular",outline:outline),images:[image],options:.init(fitTolerance:1,maxOnCurveNodes:count,maxNodes:total)),observing:{ evidence.append($0) })
            try MasterMatchSerializer.json(r).write(to:out.appendingPathComponent("private-R-result.json"))
        } catch { try Data(String(describing:error).utf8).write(to:out.appendingPathComponent("private-R-refusal.txt")) }
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys,.prettyPrinted]
        try enc.encode(evidence).write(to:out.appendingPathComponent("private-R-stages.json"))
        if let e=evidence.first, !e.sections[10].accepted {
            let ring=try MatchRing(e.boundary),fractions=ring.fractions(),lo=e.targetCuts[10],hi=e.targetCuts[11]
            let points=[ring.point(lo)]+fractions.enumerated().filter { $0.element>lo+1e-8 && $0.element<hi-1e-8 }.map { ring.spans[$0.offset].curve.start }+[ring.point(hi)]
            let v=e.sections[10].targetCurve,c=CubicBezier(start:.init(x:v[0],y:v[1]),control1:.init(x:v[2],y:v[3]),control2:.init(x:v[4],y:v[5]),end:.init(x:v[6],y:v[7]))
            let trials=[8,16,32,64].map { iterations -> [String:Any] in
                let next=MatchingCubicFitter.polish(c,points:points,budget:0.9375,iterations:iterations)
                let poly=(0...1024).map { next.point(at:Double($0)/1024) }
                let error=max(points.map { MatchGeometry.distance($0,to:poly) }.max()!,poly.map { MatchGeometry.distance($0,to:points) }.max()!)
                return ["iterations":iterations,"sampledDeviation":error,"curve":[next.start.x,next.start.y,next.control1.x,next.control1.y,next.control2.x,next.control2.y,next.end.x,next.end.y]]
            }
            try JSONSerialization.data(withJSONObject:trials,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("private-R-polish-trials.json"))
        }
    }
    /// Explicit maintenance export observes the unchanged production route.
    func testStageEvidence() throws {
        guard let destination=ProcessInfo.processInfo.environment["BEZTRACE_STAGE_EVIDENCE"] else { return }
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/matching/pair-v1")
        let images=try ["regular","bold"].map { weight in
            MatchRasterInput(id:weight,imageData:try Data(contentsOf:root.appendingPathComponent("R-\(weight).png")),transform:try JSONDecoder().decode([Double].self,from:Data(contentsOf:root.appendingPathComponent("R-\(weight).transform.json"))))
        }
        var evidence:[RasterMasterMatcher.FitEvidence]=[]
        let result=try RasterMasterMatcher.match(.init(mode:.traceBoth,axis:.init(tag:"wght",locations:[400,700]),images:images,options:.init(referencePolicy:.sharedSubdivision,fitTolerance:1,maxAdditionalOnCurveNodes:40,maxOnCurveNodes:64,maxNodes:160)),observing:{ evidence.append($0) })
        let out=URL(fileURLWithPath:destination);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys,.prettyPrinted]
        let vectors=evidence[0].originalBoundary.enumerated().dropFirst().map { i,p in
            let previous=evidence[0].originalBoundary[i-1],x=p[0]-previous[0],y=p[1]-previous[1]
            return [x,y,hypot(x,y),(x*x+y*y).squareRoot()]
        }
        try enc.encode(vectors).write(to:out.appendingPathComponent("norms.json"))
        try enc.encode(evidence).write(to:out.appendingPathComponent("stages.json"))
        try MasterMatchSerializer.json(result).write(to:out.appendingPathComponent("result.json"))
    }
}
