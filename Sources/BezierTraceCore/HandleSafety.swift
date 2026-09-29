// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum HandleSafety {
    static let maximumReachRatio = 0.9
    static let validationTolerance = 2.0

    static func isControlled(_ curve: CubicBezier, tolerance: Double) -> Bool {
        let chordVector = curve.end - curve.start
        let chord = chordVector.magnitude
        guard chord > 1e-9 else { return false }
        let first = curve.control1 - curve.start
        let second = curve.control2 - curve.end
        guard let firstDirection = first.normalized(epsilon: 1e-9),
              let secondDirection = second.normalized(epsilon: 1e-9)
        else { return true }
        let chordDirection = chordVector / chord
        let reach = first.dot(chordDirection) - second.dot(chordDirection)
        guard reach <= chord * maximumReachRatio + tolerance else { return false }
        if let triangle = ContourRefiner.handleTriangle(
            start: curve.start,
            startDirection: firstDirection,
            end: curve.end,
            endDirection: secondDirection
        ), first.magnitude > triangle.0 + tolerance || second.magnitude > triangle.1 + tolerance {
            return false
        }
        return true
    }
}
