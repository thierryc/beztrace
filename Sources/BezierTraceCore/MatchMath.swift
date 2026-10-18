// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

/// Platform libm hypot differs by one ULP on identical arm64/Intel inputs.
/// Matching uses explicitly ordered Double arithmetic and IEEE square root;
/// no coordinate quantization or fitting allowance is introduced.
enum MatchMath {
    static func length(_ x: Double, _ y: Double) -> Double {
        let largest=max(abs(x),abs(y))
        if largest == 0 { return 0 }
        if largest>=1e-150 && largest<=1e150 {
            return (x*x+y*y).squareRoot()
        }
        let a=x/largest,b=y/largest
        return largest*(a*a+b*b).squareRoot()
    }
}

extension Point2D {
    func matchDistance(to other: Point2D) -> Double { MatchMath.length(other.x-x,other.y-y) }
}
extension Vector2D {
    var matchMagnitude: Double { MatchMath.length(dx,dy) }
    func matchNormalized(epsilon: Double = 1e-12) -> Vector2D? {
        let length=matchMagnitude
        return length.isFinite && length>epsilon ? self/length : nil
    }
}
