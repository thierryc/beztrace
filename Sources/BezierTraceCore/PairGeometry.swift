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
    static func distance(_ p: Point2D,_ a: Point2D,_ b: Point2D) -> Double {
        SourceGeometryVerifier.distance(p,a,b)
    }
    static func flatten(_ ring: MatchRing,epsilon: Double) throws -> [Point2D] {
        try SourceGeometryVerifier.flatten(ring,epsilon:epsilon)
    }
    static func measure(_ a: [Point2D],_ b: [Point2D],tolerance: Double,flattenAllowance: Double) throws -> PairDeviation {
        try SourceGeometryVerifier.measure(a,b,tolerance:tolerance,flattenAllowance:flattenAllowance)
    }
    static func measure(_ source: MatchRing,_ fitted: MatchRing,tolerance: Double) throws -> PairDeviation {
        let eps=tolerance/200
        return try measure(flatten(source,epsilon:eps),flatten(fitted,epsilon:eps),tolerance:tolerance,flattenAllowance:2*eps)
    }
    static func measure(_ source: Outline,_ fitted: Outline,tolerance: Double) throws -> PairDeviation {
        guard tolerance.isFinite,tolerance>0 else { throw MasterMatchError.geometry("source measurement requires positive finite tolerance") }
        if source==fitted { return .init(lowerBound:0,upperBound:0,uncertainty:0) }
        let a=try source.contours.map(MatchRing.init),b=try fitted.contours.map(MatchRing.init)
        guard a.count==b.count else { throw MasterMatchError.topology("source measurement contour counts") }
        let pairs=try OutlineMatcher.pair(a,b,overrides:[])
        var lo=0.0,hi=0.0
        for i in a.indices {
            let m=try measure(a[i],b[pairs[i]],tolerance:tolerance)
            lo=max(lo,m.lowerBound);hi=max(hi,m.upperBound)
        }
        return .init(lowerBound:lo,upperBound:hi,uncertainty:hi-lo)
    }
}
