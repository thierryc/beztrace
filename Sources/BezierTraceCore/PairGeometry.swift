// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

public struct PairDeviation: Codable, Sendable {
    public var lowerBound: Double
    public var upperBound: Double
    public var uncertainty: Double
}

/// Independent of the fitter objective. Segment sampling uses the 1-Lipschitz
/// distance function; convex-hull flattening bounds account for BOTH curves.
enum PairGeometry {
    struct Edge { var a: Point2D; var b: Point2D; var box: Bounds }
    indirect enum Tree {
        case leaf(Bounds, [Edge])
        case branch(Bounds, Tree, Tree)
        var box: Bounds { switch self { case .leaf(let b,_), .branch(let b,_,_): return b } }
        init(_ e: [Edge]) {
            let b=e.dropFirst().reduce(e[0].box) { $0.union($1.box) }
            if e.count<=8 { self = .leaf(b,e); return }
            let x=b.width>=b.height
            let s=e.sorted { x ? $0.a.x+$0.b.x < $1.a.x+$1.b.x : $0.a.y+$0.b.y < $1.a.y+$1.b.y }
            self = .branch(b,Tree(Array(s[..<(s.count/2)])),Tree(Array(s[(s.count/2)...])))
        }
        func boxDistance(_ p: Point2D) -> Double { MatchMath.length(max(box.minX-p.x,0,p.x-box.maxX),max(box.minY-p.y,0,p.y-box.maxY)) }
        func distance(_ p: Point2D, best: Double = .infinity) -> Double {
            if boxDistance(p)>best { return best }
            switch self {
            case .leaf(_,let edges): return edges.reduce(best) { min($0,PairGeometry.distance(p,$1.a,$1.b)) }
            case .branch(_,let a,let b):
                return a.boxDistance(p)<b.boxDistance(p) ? b.distance(p,best:a.distance(p,best:best)) : a.distance(p,best:b.distance(p,best:best))
            }
        }
    }
    static func distance(_ p: Point2D,_ a: Point2D,_ b: Point2D) -> Double {
        let d=b-a;return p.matchDistance(to:a+d*min(1,max(0,(p-a).dot(d)/max(d.dot(d),1e-24))))
    }
    static func flatten(_ ring: MatchRing,epsilon: Double) throws -> [Point2D] {
        var pts=[ring.spans[0].curve.start]
        func append(_ c: CubicBezier,_ depth: Int) throws {
            if max(distance(c.control1,c.start,c.end),distance(c.control2,c.start,c.end))<=epsilon { pts.append(c.end);return }
            guard depth<20,pts.count<131072 else { throw MasterMatchError.geometry("source measurement flattening resource limit") }
            let (a,b)=c.split(at:0.5);try append(a,depth+1);try append(b,depth+1)
        }
        for s in ring.spans { if s.line { pts.append(s.curve.end) } else { try append(s.curve,0) } }
        return pts
    }
    static func measure(_ a: [Point2D],_ b: [Point2D],tolerance: Double,flattenAllowance: Double) throws -> PairDeviation {
        func tree(_ p: [Point2D]) -> Tree { Tree(zip(p,p.dropFirst()).map { Edge(a:$0.0,b:$0.1,box:Bounds(points:[$0.0,$0.1])!) }) }
        let ta=tree(a),tb=tree(b),step=tolerance/20
        var sampled=0.0,count=0
        for (p,t) in [(a,tb),(b,ta)] {
            for (s,e) in zip(p,p.dropFirst()) {
                let required=ceil(s.matchDistance(to:e)/step)
                guard required.isFinite,required<=2_000_000 else { throw MasterMatchError.geometry("source measurement sample limit") }
                let n=max(1,Int(required))
                count+=n+1;guard count<=2_000_000 else { throw MasterMatchError.geometry("source measurement sample limit") }
                for i in 0...n { sampled=max(sampled,t.distance(s.interpolated(to:e,t:Double(i)/Double(n)))) }
            }
        }
        let lower=max(0,sampled-flattenAllowance),upper=sampled+step/2+flattenAllowance
        return PairDeviation(lowerBound:lower,upperBound:upper,uncertainty:upper-lower)
    }
    static func measure(_ source: Outline,_ fitted: Outline,tolerance: Double) throws -> PairDeviation {
        if source==fitted { return .init(lowerBound:0,upperBound:0,uncertainty:0) }
        let a=try source.contours.map(MatchRing.init),b=try fitted.contours.map(MatchRing.init)
        guard a.count==b.count else { throw MasterMatchError.topology("source measurement contour counts") }
        let pairs=try OutlineMatcher.pair(a,b,overrides:[]),eps=tolerance/200
        var lo=0.0,hi=0.0
        for i in a.indices {
            let m=try measure(flatten(a[i],epsilon:eps),flatten(b[pairs[i]],epsilon:eps),tolerance:tolerance,flattenAllowance:2*eps)
            lo=max(lo,m.lowerBound);hi=max(hi,m.upperBound)
        }
        return .init(lowerBound:lo,upperBound:hi,uncertainty:hi-lo)
    }
}
