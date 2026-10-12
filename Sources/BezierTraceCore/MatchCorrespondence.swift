// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Original bounded geometric sequence alignment; no external source translated.

/// Align shape locations before fitting. Feature labels alone are insufficient:
/// a raster's rounded terminal can acquire a different label from its vector.
enum MatchCorrespondence {
    /// Existing feature-anchor neighborhood, distinct from fitting tolerance.
    static let landmarkWindow = 0.025
    struct Sample {
        var point: Point2D
        var tangent: Vector2D
    }

    static func samples(_ ring: MatchRing, count: Int = 128) -> [Sample] {
        let bounds = ring.bounds
        let points = (0...count).map { OutlineMatcher.normalized(ring.point(Double($0)/Double(count)),bounds) }
        return (0...count).map { i in
            let previous = points[i == 0 ? count-1 : i-1]
            let next = points[i == count ? 1 : i+1]
            return Sample(point:points[i],tangent:(next-previous).matchNormalized() ?? .zero)
        }
    }

    static func cost(_ a: Sample, _ b: Sample) -> Double {
        let distance = a.point.matchDistance(to:b.point)
        return distance*distance + 0.04*max(0,1-a.tangent.dot(b.tangent))
    }

    /// Strictly increasing map, with bounded local stretch (1/3...3). The
    /// endpoint fixes the chosen cyclic start; no later normalization rotates it.
    static func map(_ a: MatchRing, _ b: MatchRing) -> [(Double,Double)] {
        let x=samples(a), y=samples(b), n=x.count-1
        let width=n+1
        var dp=Array(repeating:Double.infinity,count:width*width)
        var back=Array(repeating:0,count:width*width)
        let steps=[(1,1),(1,2),(2,1),(1,3),(3,1)]
        dp[0]=cost(x[0],y[0])
        for i in 1...n { for j in max(1,i-n/3)...min(n,i+n/3) {
            let local=cost(x[i],y[j])
            for (index,step) in steps.enumerated() where i>=step.0 && j>=step.1 {
                let prior=dp[(i-step.0)*width+j-step.1]
                // Charge skipped samples too, so stretches do not win merely
                // by visiting fewer cells. Small stretch cost avoids jitter.
                let value=prior+local*Double(step.0+step.1)/2+Double(abs(step.0-step.1))*0.0002
                if value<dp[i*width+j] { dp[i*width+j]=value; back[i*width+j]=index }
            }
        } }
        var i=n,j=n, map:[(Double,Double)]=[(1,1)]
        while i>0 && j>0 {
            let step=steps[back[i*width+j]]
            i-=step.0; j-=step.1
            map.append((Double(i)/Double(n),Double(j)/Double(n)))
        }
        return map.reversed()
    }
}
