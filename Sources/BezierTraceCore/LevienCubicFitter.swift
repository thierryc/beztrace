// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independent implementation of the area/first-moment construction described
// by Raph Levien, https://raphlinus.github.io/curves/2021/03/11/bezier-fitting.html
// No Kurbo source is incorporated. Candidates require independent acceptance.
import Foundation

enum LevienCubicFitter {
    struct Moments { var area: Double; var first: Double }
    static func moments(_ curves: [CubicBezier]) -> Moments {
        var area=0.0,first=0.0
        for c in curves {
            func power(_ p: [Double]) -> [Double] {
                [p[0],3*(p[1]-p[0]),3*(p[2]-2*p[1]+p[0]),p[3]-3*p[2]+3*p[1]-p[0]]
            }
            let x=power([c.start.x,c.control1.x,c.control2.x,c.end.x])
            let y=power([c.start.y,c.control1.y,c.control2.y,c.end.y])
            let ydx=FitPolynomial.multiply(y,FitPolynomial.derivative(x))
            area+=FitPolynomial.integral(ydx)
            first+=FitPolynomial.integral(FitPolynomial.multiply(x,ydx))
        }
        return .init(area:area,first:first)
    }
    static func candidates(_ curves: [CubicBezier],start: Point2D,end: Point2D,
                           startTangent: Vector2D,endTangent: Vector2D) -> [CubicBezier] {
        let chord=end-start,length=chord.matchMagnitude
        guard length>1e-9,let u=startTangent.matchNormalized(),let v=endTangent.matchNormalized() else { return [] }
        let axis=chord/length
        func point(_ p: Point2D) -> Point2D {
            let d=(p-start)/length
            return .init(x:d.dot(axis),y:axis.cross(d))
        }
        let source=curves.map { c in CubicBezier(start:point(c.start),control1:point(c.control1),control2:point(c.control2),end:point(c.end)) }
        let c0=u.dot(axis),s0=axis.cross(u),c1=v.dot(axis),s1 = -axis.cross(v)
        let cross=s0*c1+c0*s1,m=moments(source)
        // b = N(a)/D(a) follows from matching signed area. Substitution into
        // the chord-direction first moment gives a quartic in handle a.
        let n=[20*m.area/3,-2*s0],d=[2*s1,-cross]
        let dd=FitPolynomial.multiply(d,d),nd=FitPolynomial.multiply(n,d),nn=FitPolynomial.multiply(n,n)
        let p=FitPolynomial.add(FitPolynomial.add(
            FitPolynomial.multiply([-280*m.first,34*s0,15*s0*c0],dd),
            FitPolynomial.multiply([50*s1,-(33*s0*c1+9*c0*s1),-9*cross*c0],nd)),
            FitPolynomial.multiply([-15*s1*c1,9*cross*c1],nn))
        // Also retain stationary near-misses when exact moment roots disappear.
        let stationary=FitPolynomial.add(FitPolynomial.multiply(FitPolynomial.derivative(p),d),
            FitPolynomial.scale(FitPolynomial.multiply(p,FitPolynomial.derivative(d)),-2))
        var lengths=FitPolynomial.roots(p,in:1e-8...4)+FitPolynomial.roots(stationary,in:1e-8...4)
        lengths.sort()
        var result:[CubicBezier]=[]
        func append(_ a: Double,_ b: Double) {
            guard a.isFinite,b.isFinite,a>1e-8,b>1e-8,a<=4,b<=4 else { return }
            let curve=CubicBezier(start:start,control1:start+u*(a*length),control2:end+v*(-b*length),end:end)
            if MatchGeometry.controlled(curve),!result.contains(where: { $0.control1.matchDistance(to:curve.control1)<1e-8 && $0.control2.matchDistance(to:curve.control2)<1e-8 }) { result.append(curve) }
        }
        for a in lengths {
            let denominator=FitPolynomial.value(d,a)
            if abs(denominator)>1e-10 { append(a,FitPolynomial.value(n,a)/denominator) }
        }
        // At the area equation's removable pole, solve the moment directly.
        if abs(cross)>1e-12 {
            let a=2*s1/cross
            if a>1e-8,a<=4,abs(FitPolynomial.value(n,a))<1e-10 {
                let q=[34*a*s0+15*a*a*s0*c0-280*m.first,
                       50*s1-a*(33*s0*c1+9*c0*s1)-9*a*a*cross*c0,
                       -15*s1*c1+9*a*cross*c1]
                for b in FitPolynomial.roots(q,in:1e-8...4) { append(a,b) }
            }
        }
        return result
    }
}
