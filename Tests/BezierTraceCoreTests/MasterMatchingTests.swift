// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CryptoKit
import XCTest
@testable import BezierTraceCore

final class MasterMatchingTests: XCTestCase {
    func testStorageRoundingDoesNotRejectCertifiedMonotoneCubic() {
        // A short interpolated section exposed by save/reopen qualification.
        // Its tangent triangle nearly meets the end point; three-decimal font
        // storage changes the sign of that intersection without folding it.
        let curve = CubicBezier(start:.init(x:332.2994,y:120.9038),
            control1:.init(x:333.6706,y:122.4046),control2:.init(x:334.815,y:123.855),
            end:.init(x:336.2738,y:125.2528))
        XCTAssertFalse(HandleSafety.isControlled(curve,tolerance:HandleSafety.validationTolerance))
        XCTAssertTrue(MatchGeometry.controlled(curve))
        let folded = CubicBezier(start:.init(x:0,y:0),control1:.init(x:100,y:100),
            control2:.init(x:-100,y:100),end:.init(x:10,y:0))
        XCTAssertFalse(MatchGeometry.controlled(folded))
    }
    func testExactKnotWithZeroDerivativeRemainsExact() throws {
        let points = [(0.0,0.0),(0,0),(100,0),(100,0),(100,0),(100,100),(100,100),
                      (100,100),(0,100),(0,100),(0,100),(0,0)]
        let path = Contour(nodes:points.enumerated().map { i,p in
            Node(x:p.0,y:p.1,type:i%3==0 ? .curve : .offcurve)
        })
        let ring = try MatchRing(path), fractions = ring.fractions()+[1]
        for (i,pair) in zip(fractions,fractions.dropFirst()).enumerated() {
            let section = try XCTUnwrap(ring.subspan(pair.0,pair.1))
            XCTAssertEqual(section.curve.start,ring.spans[i].curve.start)
            XCTAssertEqual(section.curve.end,ring.spans[i].curve.end)
        }
    }
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/matching/v1")

    func testFrozenMatchingCorpus() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
        for record in manifest["fixtures"] as! [[String: String]] {
            let data = try Data(contentsOf: root.appendingPathComponent(record["file"]!))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), record["sha256"])
            let request = try JSONDecoder().decode(MasterMatchRequest.self, from: data)
            if record["outcome"] == "success" {
                let first = try OutlineMatcher.match(request)
                let bytes = try MasterMatchSerializer.json(first)
                XCTAssertEqual(bytes, try MasterMatchSerializer.json(OutlineMatcher.match(request)), record["name"]!)
                XCTAssertEqual(first.reference.outline.contours.map { $0.nodes.map(\.type) }, first.target.outline.contours.map { $0.nodes.map(\.type) })
                if request.options.referencePolicy == .fixed { XCTAssertEqual(first.reference.outline, request.reference.outline) }
                else {
                    for (a, b) in zip(request.reference.outline.contours, first.reference.outline.contours) {
                        XCTAssertLessThan(MatchGeometry.deviation(try MatchRing(a), try MatchRing(b), tolerance: 1e-4), 1e-4)
                    }
                }
                XCTAssertFalse(first.interpolation.nativeHOIVerified)
                XCTAssertEqual(first.interpolation.sampleCount, 101)
                XCTAssertEqual(first.contours.map { $0.nodeIDs.count }, first.reference.outline.contours.map { $0.nodes.count })
            } else {
                XCTAssertThrowsError(try OutlineMatcher.match(request), record["name"]!) { error in
                    guard let error = error as? MasterMatchError else { return XCTFail("unexpected \(error)") }
                    switch (record["outcome"]!, error) {
                    case ("topology", .topology), ("ambiguous-contour", .ambiguousContour), ("fit", .fit), ("fit", .fitDiagnostic): break
                    default: XCTFail("wrong error for \(record["name"]!): \(error)")
                    }
                }
            }
        }
    }

    func testInterpolationRejectsCollapsedAndMismatchedStructures() throws {
        let square = Contour(nodes: [Node(x: 0, y: 0, type: .line), Node(x: 100, y: 0, type: .line),
                                      Node(x: 100, y: 100, type: .line), Node(x: 0, y: 100, type: .line)])
        let a = Outline(contours: [square])
        let b = Outline(contours: [Contour(nodes: square.nodes.map { Node(x: 100 - $0.x, y: 100 - $0.y, type: $0.type) })])
        let report = try InterpolationValidator.validate(reference: a, target: b)
        XCTAssertTrue(report.issues.contains { $0.factor == 0.5 })
        XCTAssertThrowsError(try InterpolationValidator.interpolate(reference: a, target: Outline(contours: []), factor: 0.5))
        XCTAssertThrowsError(try InterpolationValidator.interpolate(reference: a, target: a, factor: .nan))
    }

    func testUntrustedGeometryIsRejectedBeforeMatching() throws {
        var request = try JSONDecoder().decode(MasterMatchRequest.self, from: Data(contentsOf: root.appendingPathComponent("identical.json")))
        request.reference.outline.contours[0].nodes[0].x = .infinity
        XCTAssertThrowsError(try OutlineMatcher.match(request))
        request.reference.outline.contours[0].nodes[0].x = 0
        request.options.contourPairs = [10]
        XCTAssertThrowsError(try OutlineMatcher.match(request))
        request.options.contourPairs = []
        request.options.startNodes = [999]
        XCTAssertThrowsError(try OutlineMatcher.match(request))
    }
}
