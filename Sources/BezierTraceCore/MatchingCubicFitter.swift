// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independently written least-squares fitting for the optional matching API.
import Foundation

enum MatchingCubicFitter {
    /// Bounded derivative-free minimax fallback. Moving one handle coordinate
    /// alone can worsen the active maximum even when a coupled move improves
    /// it; least squares and coordinate descent can both stop prematurely.
    static func minimax(_ initial: CubicBezier, points: [Point2D], budget: Double,
                        verticalEnvelope: Bounds? = nil, iterations: Int = 192) -> CubicBezier {
        func curve(_ x: [Double]) -> CubicBezier {
            .init(start:initial.start,control1:.init(x:x[0],y:x[1]),
                  control2:.init(x:x[2],y:x[3]),end:initial.end)
        }
        func error(_ x: [Double]) -> Double {
            let c=curve(x)
            guard MatchGeometry.controlled(c) else { return .infinity }
            if let envelope=verticalEnvelope {
                let b=c.bounds
                guard b.minY>=envelope.minY && b.maxY<=envelope.maxY else { return .infinity }
            }
            let poly=(0...128).map { c.point(at:Double($0)/128) }
            return max(points.map { MatchGeometry.distance($0,to:poly) }.max() ?? 0,
                       poly.map { MatchGeometry.distance($0,to:points) }.max() ?? 0)
        }
        struct Vertex { var x: [Double]; var error: Double; var order: Int }
        var order=0
        func vertex(_ x: [Double]) -> Vertex { defer { order+=1 }; return .init(x:x,error:error(x),order:order) }
        let base=[initial.control1.x,initial.control1.y,initial.control2.x,initial.control2.y]
        var simplex=[vertex(base)]
        let step=max(budget,initial.start.matchDistance(to:initial.end)/128)
        for i in 0..<4 {
            var positive=base,negative=base;positive[i]+=step;negative[i]-=step
            let a=vertex(positive),b=vertex(negative)
            simplex.append(a.error<=b.error ? a : b)
        }
        for _ in 0..<iterations {
            simplex.sort { $0.error == $1.error ? $0.order<$1.order : $0.error<$1.error }
            if simplex[0].error<=budget { break }
            let center=(0..<4).map { coordinate in simplex.prefix(4).reduce(0) { $0+$1.x[coordinate] }/4 }
            func moved(_ x: [Double],_ factor: Double) -> Vertex {
                vertex(zip(center,x).map { $0+factor*($1-$0) })
            }
            let reflection=moved(simplex[4].x,-1)
            if reflection.error<simplex[0].error {
                let expansion=moved(reflection.x,2)
                simplex[4]=expansion.error<reflection.error ? expansion : reflection
            } else if reflection.error<simplex[3].error { simplex[4]=reflection }
            else {
                let outside=reflection.error<simplex[4].error
                let contraction=moved(outside ? reflection.x : simplex[4].x,0.5)
                if contraction.error<(outside ? reflection.error : simplex[4].error) { simplex[4]=contraction }
                else {
                    let best=simplex[0].x
                    for i in 1..<5 { simplex[i]=vertex(zip(best,simplex[i].x).map { $0+0.5*($1-$0) }) }
                }
            }
        }
        let best=simplex.min { $0.error == $1.error ? $0.order<$1.order : $0.error<$1.error }!
        return best.error<error(base) ? curve(best.x) : initial
    }
    static func polish(_ initial: CubicBezier,points: [Point2D],budget: Double,
                       verticalEnvelope: Bounds? = nil,iterations: Int = 8) -> CubicBezier {
        func error(_ c: CubicBezier) -> Double {
            let poly=(0...64).map { c.point(at:Double($0)/64) }
            return max(points.map { MatchGeometry.distance($0,to:poly) }.max() ?? 0,
                       poly.map { MatchGeometry.distance($0,to:points) }.max() ?? 0)
        }
        var curve=initial, value=error(initial), step=max(budget,initial.start.matchDistance(to:initial.end)/64)
        for _ in 0..<iterations {
            var changed=false
            for control in 0..<2 {
                for direction in [Vector2D(dx:1,dy:0),Vector2D(dx:-1,dy:0),Vector2D(dx:0,dy:1),Vector2D(dx:0,dy:-1)] {
                    var candidate=curve
                    if control == 0 { candidate.control1=candidate.control1+direction*step }
                    else { candidate.control2=candidate.control2+direction*step }
                    guard MatchGeometry.controlled(candidate) else { continue }
                    if let envelope=verticalEnvelope {
                        let bounds=candidate.bounds, rounding=max(1,envelope.height)*Double.ulpOfOne*64
                        guard bounds.minY>=envelope.minY-rounding && bounds.maxY<=envelope.maxY+rounding else { continue }
                    }
                    let next=error(candidate)
                    if next<value-1e-7 { curve=candidate; value=next; changed=true }
                }
            }
            if value<=budget { break }
            if !changed { step *= 0.5 }
        }
        return curve
    }
    /// Fixed endpoints, free handle vectors, monotonically reparameterized
    /// least squares. Does not insert points or alter the reference geometry.
    static func fit(_ points: [Point2D], refinementBudget: Double? = nil, startTangent: Vector2D? = nil, endTangent: Vector2D? = nil) -> CubicBezier {
        let a=points[0], b=points.last!
        var ts=[0.0], length=0.0
        for i in 1..<points.count { length += points[i].matchDistance(to:points[i-1]); ts.append(length) }
        ts=ts.map { $0/max(length,1e-12) }
        var curve=lineCubic(from:a,to:b)
        var best: CubicBezier? = nil, bestError=Double.infinity
        for iteration in 0..<(refinementBudget == nil ? 8 : 256) {
            var xx=0.0, xy=0.0, yy=0.0
            var dx=Vector2D.zero, dy=Vector2D.zero
            for (p,t) in zip(points,ts) {
                let u=1-t, v=3*u*u*t, w=3*u*t*t
                let base=a+(b-a)*(w+t*t*t)
                let d=p-base
                xx += v*v; xy += v*w; yy += w*w; dx=dx+d*v; dy=dy+d*w
            }
            let determinant=xx*yy-xy*xy
            if determinant>1e-14 {
                if let first=startTangent, let second=endTangent {
                    let cross=xy*first.dot(second), determinant=xx*yy-cross*cross
                    if determinant>1e-14 {
                        let x=dx.dot(first), y=dy.dot(second)
                        let alpha=max(0,(x*yy-y*cross)/determinant), beta=max(0,(y*xx-x*cross)/determinant)
                        curve=CubicBezier(start:a,control1:a+first*alpha,control2:b+second*beta,end:b)
                    }
                } else {
                    let first=(dx*yy-dy*xy)/determinant, second=(dy*xx-dx*xy)/determinant
                    curve=CubicBezier(start:a,control1:a+first,control2:b+second,end:b)
                }
            }
            if let budget=refinementBudget, iteration % 8 == 7, MatchGeometry.controlled(curve) {
                let poly=(0...64).map { curve.point(at:Double($0)/64) }
                let error=max(points.map { MatchGeometry.distance($0,to:poly) }.max() ?? 0,
                              poly.map { MatchGeometry.distance($0,to:points) }.max() ?? 0)
                if error<bestError { best=curve; bestError=error }
                if error<=budget { break }
            }
            for i in 1..<(ts.count-1) {
                let t=ts[i], u=1-t, p=curve.point(at:t), derivative=curve.derivative(at:t)
                let second=((curve.control2-curve.control1)-(curve.control1-a))*(6*u)
                    + ((b-curve.control2)-(curve.control2-curve.control1))*(6*t)
                let d=p-points[i], denominator=derivative.dot(derivative)+d.dot(second)
                if denominator>1e-12 { ts[i]=min(ts[i+1],max(ts[i-1],t-d.dot(derivative)/denominator)) }
            }
        }
        return best ?? curve
    }
}
