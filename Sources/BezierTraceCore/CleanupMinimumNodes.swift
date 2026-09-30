// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

enum CleanupMinimumNodes {
    private static let closureEpsilon = 1e-6
    private static let geometryEpsilon = 1e-9

    static func ensureThreeOnCurves(_ path: BezierPathContour) -> BezierPathContour {
        guard path.segments.count == 2,
              path.segments.allSatisfy({ segment in
                  segment.cubic.isFinite
                      && segment.cubic.start.distance(to: segment.cubic.end) > geometryEpsilon
              }),
              path.segments[0].cubic.end.distance(to: path.segments[1].cubic.start)
                  <= closureEpsilon,
              path.segments[1].cubic.end.distance(to: path.segments[0].cubic.start)
                  <= closureEpsilon,
              abs(CleanupDirection.signedArea(path)) > geometryEpsilon
        else { return path }

        var splitIndex = 0
        var greatestLength = controlPolygonLength(path.segments[0].cubic)
        for index in path.segments.indices.dropFirst() {
            let length = controlPolygonLength(path.segments[index].cubic)
            if length > greatestLength {
                splitIndex = index
                greatestLength = length
            }
        }

        let segment = path.segments[splitIndex]
        let halves = segment.cubic.split(at: 0.5)
        var segments = path.segments
        segments.replaceSubrange(
            splitIndex...splitIndex,
            with: [
                PathSegment(cubic: halves.0, isLine: segment.isLine),
                PathSegment(cubic: halves.1, isLine: segment.isLine),
            ]
        )
        return BezierPathContour(segments: segments)
    }

    private static func controlPolygonLength(_ curve: CubicBezier) -> Double {
        curve.start.distance(to: curve.control1)
            + curve.control1.distance(to: curve.control2)
            + curve.control2.distance(to: curve.end)
    }
}
