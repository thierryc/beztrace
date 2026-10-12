// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independently written minimum-width enclosing-strip fit for fixed lines.

enum MatchingLineFitter {
    /// Every finite sample lies in the convex hull. A minimum-width enclosing
    /// strip has a supporting hull edge; examine all such orientations exactly.
    /// The half-width is also a lower bound for any line on this assigned span.
    static func fit(_ points: [Point2D]) -> (curve: CubicBezier, lowerBound: Double)? {
        guard points.count>=2 else { return nil }
        let sorted=points.sorted { $0.x == $1.x ? $0.y<$1.y : $0.x<$1.x }
        var unique:[Point2D]=[]
        for p in sorted where unique.last != p { unique.append(p) }
        guard unique.count>=2 else { return nil }
        func chain(_ input: [Point2D]) -> [Point2D] {
            var result:[Point2D]=[]
            for p in input {
                while result.count>=2 && (result.last!-result[result.count-2]).cross(p-result.last!)<=0 { result.removeLast() }
                result.append(p)
            }
            return result
        }
        let hull=Array(chain(unique).dropLast())+Array(chain(unique.reversed()).dropLast())
        let chord=points.last!-points[0]
        var best:(CubicBezier,Double)?
        for i in hull.indices {
            guard var direction=(hull[(i+1)%hull.count]-hull[i]).matchNormalized() else { continue }
            if direction.dot(chord)<0 { direction = -direction }
            let normal=Vector2D(dx:-direction.dy,dy:direction.dx), origin=points[0]
            let across=points.map { ($0-origin).dot(normal) }
            let along=points.map { ($0-origin).dot(direction) }
            let low=across.min()!, high=across.max()!, width=(high-low)/2
            if best == nil || width<best!.1 {
                let center=normal*((high+low)/2)
                best=(lineCubic(from:origin+direction*along.min()!+center,
                    to:origin+direction*along.max()!+center),width)
            }
        }
        return best.map { ($0.0,$0.1) }
    }
}
