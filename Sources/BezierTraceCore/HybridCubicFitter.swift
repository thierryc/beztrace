// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

/// Fixed endpoints and directed tangents. Proposals never certify themselves:
/// both algorithms pass the same original-source verifier before being used.
enum HybridCubicFitter {
    enum Method: String { case levien, refinedLeastSquares }
    struct Result { let curve: CubicBezier; let method: Method; let report: SourceGeometryVerifier.CubicReport }
    static func fit(_ curves: [CubicBezier],tolerance: Double) -> Result? {
        guard let first=curves.first,let last=curves.last,
              let a=first.derivative(at:0).matchNormalized(),let b=last.derivative(at:1).matchNormalized(),
              let source=try? SourceGeometryVerifier.prepare(curves,tolerance:tolerance) else { return nil }
        let points=curves.flatMap { c in (0..<33).map { c.point(at:Double($0)/33) } }+[last.end]
        return fit(curves,points:points,source:source,tolerance:tolerance,start:first.start,end:last.end,startTangent:a,endTangent:b)
    }
    static func fit(polyline: [Point2D],tolerance: Double,start: Point2D,end: Point2D,
                    startTangent: Vector2D,endTangent: Vector2D) -> Result? {
        guard let source=try? SourceGeometryVerifier.prepare(polyline:polyline,tolerance:tolerance) else { return nil }
        var points=polyline;points[0]=start;points[points.count-1]=end
        // Include the endpoint connectors in the moments, while measuring
        // acceptance against the unmodified original boundary.
        let path=[start]+polyline+[end]
        let curves=zip(path,path.dropFirst()).map { lineCubic(from:$0,to:$1) }
        return fit(curves,points:points,source:source,tolerance:tolerance,start:start,end:end,startTangent:startTangent,endTangent:endTangent)
    }
    private static func fit(_ curves: [CubicBezier],points: [Point2D],source: SourceGeometryVerifier.Span,
                            tolerance: Double,start: Point2D,end: Point2D,startTangent: Vector2D,endTangent: Vector2D) -> Result? {
        guard let a=startTangent.matchNormalized(),let b=endTangent.matchNormalized() else { return nil }
        func accept(_ c: CubicBezier,_ method: Method) -> Result? {
            guard let report=try? SourceGeometryVerifier.verify(c,source:source,tolerance:tolerance,
                start:start,end:end,startTangent:a,endTangent:b),report.accepted else { return nil }
            return .init(curve:c,method:method,report:report)
        }
        let candidates=LevienCubicFitter.candidates(curves,start:start,end:end,startTangent:a,endTangent:b)
        // Order by a cheap diagnostic; this is never the acceptance decision.
        var ranked:[(index:Int,curve:CubicBezier,error:Double)]=[]
        for (index,c) in candidates.enumerated() {
            let poly=(0...32).map { c.point(at:Double($0)/32) }
            ranked.append((index,c,SourceGeometryVerifier.sampledOrderedDeviation(points,poly)))
        }
        ranked.sort { lhs,rhs in lhs.error == rhs.error ? lhs.index<rhs.index : lhs.error<rhs.error }
        for (_,candidate,_) in ranked { if let result=accept(candidate,.levien) { return result } }
        let fallback=MatchingCubicFitter.fit(points,refinementBudget:tolerance*0.8,startTangent:a,endTangent:-b)
        return accept(fallback,.refinedLeastSquares)
    }
}
