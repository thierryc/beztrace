// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independent source-distance acceptance, separate from all fitting objectives.
import Foundation

/// Bounds bidirectional geometric distance to immutable original boundaries.
/// This is a Hausdorff-style bound; topology and ordered correspondence are
/// separate checks. Resource exhaustion is a refusal, never a passing estimate.
enum SourceGeometryVerifier {
    static func valid(_ point: Point2D) -> Bool {
        point.isFinite && abs(point.x)<=1e9 && abs(point.y)<=1e9
    }
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
            case .leaf(_,let edges): return edges.reduce(best) { min($0,SourceGeometryVerifier.distance(p,$1.a,$1.b)) }
            case .branch(_,let a,let b):
                return a.boxDistance(p)<b.boxDistance(p) ? b.distance(p,best:a.distance(p,best:best)) : a.distance(p,best:b.distance(p,best:best))
            }
        }
    }
    static func distance(_ p: Point2D,_ a: Point2D,_ b: Point2D) -> Double {
        let d=b-a,denominator=d.dot(d)
        guard denominator>0 else { return p.matchDistance(to:a) }
        return p.matchDistance(to:a+d*min(1,max(0,(p-a).dot(d)/denominator)))
    }
    private static func tree(_ p: [Point2D]) -> Tree {
        Tree(zip(p,p.dropFirst()).map { Edge(a:$0.0,b:$0.1,box:Bounds(points:[$0.0,$0.1])!) })
    }
    static func flatten(_ ring: MatchRing,epsilon: Double) throws -> [Point2D] {
        guard epsilon.isFinite,epsilon>0,!ring.spans.isEmpty,ring.spans.count<=4096,
              ring.spans.allSatisfy({ [$0.curve.start,$0.curve.control1,$0.curve.control2,$0.curve.end].allSatisfy(valid) }) else {
            throw MasterMatchError.geometry("source measurement requires finite bounded curves and positive flatness")
        }
        let coordinateScale=ring.spans.reduce(1.0) { scale,span in
            max(scale,abs(span.curve.start.x),abs(span.curve.start.y),abs(span.curve.end.x),abs(span.curve.end.y))
        }
        // Only permit storage/arithmetic rounding at joins. Preserve even those
        // tiny connectors explicitly; the measurement rounding reserve covers
        // their distance to the original curve union.
        let connectionLimit=coordinateScale*Double.ulpOfOne*8
        guard zip(ring.spans,ring.spans.dropFirst()).allSatisfy({ $0.curve.end.matchDistance(to:$1.curve.start)<=connectionLimit }) else {
            throw MasterMatchError.geometry("source measurement requires connected spans")
        }
        var pts=[ring.spans[0].curve.start]
        func append(_ c: CubicBezier,_ depth: Int) throws {
            guard pts.count<131072 else { throw MasterMatchError.geometry("source measurement flattening resource limit") }
            if max(distance(c.control1,c.start,c.end),distance(c.control2,c.start,c.end))<=epsilon { pts.append(c.end);return }
            guard depth<20,pts.count<131072 else { throw MasterMatchError.geometry("source measurement flattening resource limit") }
            let (a,b)=c.split(at:0.5);try append(a,depth+1);try append(b,depth+1)
        }
        for s in ring.spans {
            if pts.last != s.curve.start { pts.append(s.curve.start) }
            guard pts.count<131072 else { throw MasterMatchError.geometry("source measurement flattening resource limit") }
            if s.line { pts.append(s.curve.end) } else { try append(s.curve,0) }
        }
        return pts
    }
    static func measure(_ a: [Point2D],_ b: [Point2D],tolerance: Double,flattenAllowance: Double) throws -> PairDeviation {
        guard tolerance.isFinite,tolerance>0,flattenAllowance.isFinite,flattenAllowance>=0,
              (2...131073).contains(a.count),(2...131073).contains(b.count),
              a.allSatisfy(valid),b.allSatisfy(valid) else {
            throw MasterMatchError.geometry("source measurement requires bounded finite polylines and positive tolerance")
        }
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
        let scale=(a+b).reduce(1.0) { max($0,abs($1.x),abs($1.y)) }
        let rounding=scale*Double.ulpOfOne*64
        let lower=max(0,sampled-flattenAllowance-rounding),upper=sampled+step/2+flattenAllowance+rounding
        return PairDeviation(lowerBound:lower,upperBound:upper,uncertainty:upper-lower)
    }

    /// Immutable source evidence is prepared once, independently of candidates.
    struct Span {
        let points: [Point2D]
        let flattenAllowance: Double
        let inflectionChanges: Int
    }
    static func prepare(_ curves: [CubicBezier],tolerance: Double) throws -> Span {
        let spans=curves.map { MatchSpan(curve:$0,line:false,startSource:nil,controlSources:[nil,nil],smooth:false) }
        let points=try flatten(MatchRing(spans:spans),epsilon:tolerance/200)
        return .init(points:points,flattenAllowance:tolerance/200,
                     inflectionChanges:changes(curves.flatMap(turnSigns)))
    }
    static func prepare(polyline: [Point2D],tolerance: Double) throws -> Span {
        guard tolerance.isFinite,tolerance>0,(2...131073).contains(polyline.count),polyline.allSatisfy(valid) else {
            throw MasterMatchError.geometry("invalid original fitting boundary")
        }
        var signs:[Int]=[]
        if polyline.count>2 {
            for i in 1..<(polyline.count-1) {
                let a=polyline[i]-polyline[i-1],b=polyline[i+1]-polyline[i],c=a.cross(b)
                if abs(c)>1e-12*max(1,a.matchMagnitude*b.matchMagnitude) { signs.append(c>0 ? 1 : -1) }
            }
        }
        return .init(points:polyline,flattenAllowance:0,inflectionChanges:changes(signs))
    }
    struct CubicReport {
        let deviation: PairDeviation
        /// Sampled normalized-arc correspondence diagnostic, not a Fréchet proof.
        let orderedSampleDeviation: Double
        let accepted: Bool
    }
    static func verify(_ curve: CubicBezier,source: Span,tolerance: Double,
                       start: Point2D,end: Point2D,startTangent: Vector2D?,endTangent: Vector2D?) throws -> CubicReport {
        guard curve.isFinite,MatchGeometry.controlled(curve),
              curve.start.matchDistance(to:start)<=1e-8,curve.end.matchDistance(to:end)<=1e-8 else {
            throw MasterMatchError.geometry("fitted cubic violates endpoints or handle safety")
        }
        for (actual,expected) in [(curve.derivative(at:0),startTangent),(curve.derivative(at:1),endTangent)] {
            if let expected {
                guard actual.dot(expected)>0,angleBetween(actual,expected)<Double.pi/18000 else {
                    throw MasterMatchError.geometry("fitted cubic violates protected tangent")
                }
            }
        }
        let fitted=try flatten(MatchRing(spans:[.init(curve:curve,line:false,startSource:nil,controlSources:[nil,nil],smooth:false)]),epsilon:tolerance/200)
        let ordered=sampledOrderedDeviation(source.points,fitted)
        let allowance=source.flattenAllowance+tolerance/200
        let combined=source.points+fitted,bounds=Bounds(points:combined)!
        let rounding=combined.reduce(1.0) { max($0,abs($1.x),abs($1.y)) }*Double.ulpOfOne*64
        // A vertex farther than the budget is already a sufficient refusal
        // witness. The bounding-box diameter supplies a conservative (loose)
        // upper bound; no expensive dense measurement is needed for rejection.
        let originalTree=tree(source.points),fittedTree=tree(fitted)
        let witness=max(source.points.map { fittedTree.distance($0) }.max() ?? 0,
                        fitted.map { originalTree.distance($0) }.max() ?? 0)
        if witness-allowance-rounding>tolerance {
            let lower=max(0,witness-allowance-rounding)
            let upper=MatchMath.length(bounds.width,bounds.height)+allowance+rounding
            return .init(deviation:.init(lowerBound:lower,upperBound:upper,uncertainty:upper-lower),
                         orderedSampleDeviation:ordered,accepted:false)
        }
        let deviation=try measure(source.points,fitted,tolerance:tolerance,flattenAllowance:allowance)
        return .init(deviation:deviation,orderedSampleDeviation:ordered,
            accepted:deviation.upperBound<=tolerance && ordered<=tolerance
                && changes(turnSigns(curve))<=source.inflectionChanges)
    }
    static func sampledOrderedDeviation(_ a: [Point2D],_ b: [Point2D]) -> Double {
        func samples(_ p: [Point2D]) -> [Point2D] {
            var lengths=[0.0]
            for i in 1..<p.count { lengths.append(lengths.last!+p[i].matchDistance(to:p[i-1])) }
            var index=0
            return (0...256).map { step in
                let at=lengths.last!*Double(step)/256
                while index+1<lengths.count-1 && lengths[index+1]<at { index+=1 }
                let t=(at-lengths[index])/max(lengths[index+1]-lengths[index],1e-24)
                return p[index].interpolated(to:p[index+1],t:min(1,max(0,t)))
            }
        }
        return zip(samples(a),samples(b)).map { $0.matchDistance(to:$1) }.max() ?? .infinity
    }
    private static func changes(_ signs: [Int]) -> Int { zip(signs,signs.dropFirst()).filter { $0 != $1 }.count }
    private static func turnSigns(_ c: CubicBezier) -> [Int] {
        let chord:Vector2D=c.end-c.start
        let middle:Vector2D=c.control2-c.control1
        let d:Vector2D=c.control1-c.start
        let a:Vector2D=chord-middle*3
        let b:Vector2D=middle-d
        // Curvature sign is a quadratic; include roots to avoid hiding a narrow
        // inflection between uniformly sampled parameters.
        let coefficients:[Double]=[d.cross(b),d.cross(a),b.cross(a)]
        let roots=FitPolynomial.roots(coefficients,in:0...1)
        var cuts:[Double]=[0]
        cuts.append(contentsOf:roots.filter { $0>0 && $0<1 });cuts.append(1)
        var signs:[Int]=[]
        for (lo,hi) in zip(cuts,cuts.dropFirst()) {
            let t:Double=(lo+hi)/2
            let value=FitPolynomial.value(coefficients,t)
            if abs(value)>=1e-12 { signs.append(value>0 ? 1 : -1) }
        }
        return signs
    }
}
