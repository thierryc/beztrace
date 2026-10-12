// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

enum MatchBoundarySampling {
    /// Project endpoints onto their local source boundary and retain cyclic
    /// order. This assigns an objective span; final full-source checks decide
    /// acceptance, including any imperfect projection or correspondence.
    static func span(_ poly: [Point2D],from start: Point2D,to end: Point2D) -> [Point2D] {
        func closest(_ p: Point2D) -> (index:Int,t:Double,point:Point2D) {
            var best=(index:0,t:0.0,point:poly[0]),distance=Double.infinity
            for i in 0..<(poly.count-1) {
                let d=poly[i+1]-poly[i],t=min(1,max(0,(p-poly[i]).dot(d)/max(d.dot(d),1e-24)))
                let q=poly[i]+d*t,next=p.matchDistance(to:q)
                if next<distance { best=(i,t,q);distance=next }
            }
            return best
        }
        let a=closest(start),b=closest(end),count=poly.count-1
        if a.index==b.index && a.t<b.t { return [a.point,b.point] }
        var points=[a.point],index=(a.index+1)%count
        for _ in 0..<count {
            points.append(poly[index])
            if index==b.index { break }
            index=(index+1)%count
        }
        points.append(b.point);return points
    }
}
