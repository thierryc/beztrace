// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

/// Local coordinate constraints avoid moving an entire glyph to repair one
/// raster extremum. The caller must remeasure both original and raster sources.
enum PairEnvelopeFitter {
    static func fit(_ outline: Outline, source: Outline, bounds: Bounds, tolerance: Double) throws -> Outline {
        func clamp(_ point: Point2D) -> Point2D {
            .init(x:point.x,y:min(bounds.maxY,max(bounds.minY,point.y)))
        }
        let originals=try source.contours.map(MatchRing.init),fitted=try outline.contours.map(MatchRing.init)
        let pairs=try OutlineMatcher.pair(fitted,originals,overrides:[])
        return Outline(contours:try outline.contours.enumerated().map { ci,contour in
            var ring=try MatchRing(contour)
            var boundary=originals[pairs[ci]]
            if boundary.area*ring.area<0 { boundary=boundary.reversed() }
            let poly=try PairGeometry.flatten(boundary,epsilon:tolerance/200)
            for i in ring.spans.indices {
                let original=ring.spans[i].curve
                guard original.bounds.minY<bounds.minY || original.bounds.maxY>bounds.maxY else { continue }
                if ring.spans[i].line {
                    ring.spans[i].curve=lineCubic(from:clamp(original.start),to:clamp(original.end))
                    continue
                }
                func candidate(_ fraction: Double) -> CubicBezier {
                    .init(start:clamp(original.start),
                          control1:original.control1.interpolated(to:clamp(original.control1),t:fraction),
                          control2:original.control2.interpolated(to:clamp(original.control2),t:fraction),
                          end:clamp(original.end))
                }
                // Analytic extrema constrain the curve, not its control polygon.
                // Keep valid controls outside the envelope whenever possible.
                var low=0.0,high=1.0
                for _ in 0..<48 {
                    let mid=(low+high)/2,b=candidate(mid).bounds
                    if b.minY>=bounds.minY && b.maxY<=bounds.maxY { high=mid } else { low=mid }
                }
                let bounded=candidate(high)
                let points=MatchBoundarySampling.span(poly,from:original.start,to:original.end)
                ring.spans[i].curve=MatchingCubicFitter.minimax(bounded,points:points,
                    budget:tolerance/2,verticalEnvelope:bounds)
            }
            return ring.serialized().0
        })
    }

}
