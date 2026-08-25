// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupChamfer {
    private static let collinearThreshold = 0.95

    static func chamfer(_ path: BezierPathContour, size: Double, minimumEdge: Double) -> BezierPathContour {
        guard size > 0, path.segments.count >= 2 else { return path }
        let count = path.segments.count
        var bevel = Array(repeating: false, count: count)
        for index in 0..<count {
            let previous = (index + count - 1) % count
            let incoming = path.segments[previous]
            let outgoing = path.segments[index]
            guard incoming.isLine, outgoing.isLine else { continue }
            let first = incoming.cubic.end - incoming.cubic.start
            let second = outgoing.cubic.end - outgoing.cubic.start
            let firstLength = first.magnitude
            let secondLength = second.magnitude
            guard firstLength >= max(minimumEdge, 2 * size),
                  secondLength >= max(minimumEdge, 2 * size),
                  abs(first.dot(second) / (firstLength * secondLength)) <= collinearThreshold
            else { continue }
            bevel[index] = true
        }
        var trimmed = path.segments
        for index in 0..<count where trimmed[index].isLine {
            let line = path.segments[index].cubic
            guard let direction = (line.end - line.start).normalized(epsilon: 1e-9) else { continue }
            let start = bevel[index] ? line.start + direction * size : line.start
            let end = bevel[(index + 1) % count] ? line.end + direction * -size : line.end
            trimmed[index].cubic = lineCubic(from: start, to: end)
        }
        var result: [PathSegment] = []
        result.reserveCapacity(count + bevel.filter { $0 }.count)
        for index in 0..<count {
            if bevel[index] {
                let previous = (index + count - 1) % count
                result.append(PathSegment(
                    cubic: lineCubic(from: trimmed[previous].cubic.end, to: trimmed[index].cubic.start),
                    isLine: true
                ))
            }
            result.append(trimmed[index])
        }
        return BezierPathContour(segments: result)
    }
}
