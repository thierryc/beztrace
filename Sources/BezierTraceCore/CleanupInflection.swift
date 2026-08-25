// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum CleanupInflection {
    private static let parameterMargin = 0.15
    private static let minimumLobeTurn = 55.0 * Double.pi / 180
    private static let minimumChord = 40.0
    private static let minimumSplitDistance = 28.0

    static func splitInflections(_ path: BezierPathContour, grid: Double) -> BezierPathContour {
        var result: [PathSegment] = []
        for segment in path.segments {
            guard !segment.isLine, let parameter = splitParameter(segment.cubic) else {
                result.append(segment)
                continue
            }
            let halves = segment.cubic.split(at: parameter)
            let point = halves.0.end
            let snapped = grid > 0
                ? Point2D(x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
                : point
            let delta = snapped - point
            var left = halves.0
            left.control2 = left.control2 + delta
            left.end = snapped
            var right = halves.1
            right.start = snapped
            right.control1 = right.control1 + delta
            result.append(PathSegment(cubic: left, isLine: false))
            result.append(PathSegment(cubic: right, isLine: false))
        }
        return BezierPathContour(segments: result)
    }

    static func splitParameter(_ curve: CubicBezier) -> Double? {
        guard curve.start.distance(to: curve.end) >= minimumChord else { return nil }
        var best: (parameter: Double, weakestTurn: Double)?
        for parameter in inflectionParameters(curve)
        where parameter > parameterMargin && parameter < 1 - parameterMargin {
            let point = curve.point(at: parameter)
            guard point.distance(to: curve.start) >= minimumSplitDistance,
                  point.distance(to: curve.end) >= minimumSplitDistance
            else { continue }
            let weakest = min(
                lobeTurn(curve, from: 0, to: parameter),
                lobeTurn(curve, from: parameter, to: 1)
            )
            guard weakest >= minimumLobeTurn else { continue }
            if best == nil || weakest >= best!.weakestTurn { best = (parameter, weakest) }
        }
        return best?.parameter
    }

    private static func inflectionParameters(_ curve: CubicBezier) -> [Double] {
        func cross(_ t: Double) -> Double {
            let first = curve.derivative(at: t)
            let second = secondDerivative(curve, at: t)
            return first.cross(second)
        }
        let first = cross(0)
        let middle = cross(0.5)
        let last = cross(1)
        let constant = first
        let quadratic = 2 * first - 4 * middle + 2 * last
        let linear = last - first - quadratic
        var roots: [Double] = []
        if abs(quadratic) < 1e-9 {
            if abs(linear) > 1e-12 { roots.append(-constant / linear) }
        } else {
            let discriminant = linear * linear - 4 * quadratic * constant
            if discriminant >= 0 {
                let squareRoot = sqrt(discriminant)
                roots.append((-linear + squareRoot) / (2 * quadratic))
                roots.append((-linear - squareRoot) / (2 * quadratic))
            }
        }
        return roots.filter { $0 > 0 && $0 < 1 }
    }

    private static func secondDerivative(_ curve: CubicBezier, at t: Double) -> Vector2D {
        let first = Vector2D(
            dx: curve.control2.x - 2 * curve.control1.x + curve.start.x,
            dy: curve.control2.y - 2 * curve.control1.y + curve.start.y
        )
        let second = Vector2D(
            dx: curve.end.x - 2 * curve.control2.x + curve.control1.x,
            dy: curve.end.y - 2 * curve.control2.y + curve.control1.y
        )
        return first * (6 * (1 - t)) + second * (6 * t)
    }

    private static func lobeTurn(_ curve: CubicBezier, from start: Double, to end: Double) -> Double {
        var total = 0.0
        var previous = angle(curve.derivative(at: start))
        for step in 1...32 {
            let parameter = start + (end - start) * Double(step) / 32
            let current = angle(curve.derivative(at: parameter))
            var delta = current - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            total += abs(delta)
            previous = current
        }
        return total
    }

    private static func angle(_ vector: Vector2D) -> Double {
        atan2(vector.dy, vector.dx)
    }
}
