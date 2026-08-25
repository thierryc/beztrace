// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct Point2D: Equatable, Sendable {
    var x: Double
    var y: Double

    var isFinite: Bool { x.isFinite && y.isFinite }

    func distance(to other: Point2D) -> Double {
        hypot(other.x - x, other.y - y)
    }

    func interpolated(to other: Point2D, t: Double) -> Point2D {
        Point2D(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    static func deterministicLessThan(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }

    static func + (point: Point2D, vector: Vector2D) -> Point2D {
        Point2D(x: point.x + vector.dx, y: point.y + vector.dy)
    }

    static func - (lhs: Point2D, rhs: Point2D) -> Vector2D {
        Vector2D(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}

struct Vector2D: Equatable, Sendable {
    var dx: Double
    var dy: Double

    static let zero = Vector2D(dx: 0, dy: 0)

    var isFinite: Bool { dx.isFinite && dy.isFinite }
    var magnitude: Double { hypot(dx, dy) }

    func dot(_ other: Vector2D) -> Double {
        dx * other.dx + dy * other.dy
    }

    func cross(_ other: Vector2D) -> Double {
        dx * other.dy - dy * other.dx
    }

    func normalized(epsilon: Double = 1e-12) -> Vector2D? {
        let length = magnitude
        guard length.isFinite, length > epsilon else { return nil }
        return self / length
    }

    static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func - (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }

    static prefix func - (vector: Vector2D) -> Vector2D {
        Vector2D(dx: -vector.dx, dy: -vector.dy)
    }

    static func * (vector: Vector2D, scalar: Double) -> Vector2D {
        Vector2D(dx: vector.dx * scalar, dy: vector.dy * scalar)
    }

    static func / (vector: Vector2D, scalar: Double) -> Vector2D {
        Vector2D(dx: vector.dx / scalar, dy: vector.dy / scalar)
    }
}

struct Bounds: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init?<C: Collection>(points: C) where C.Element == Point2D {
        guard let first = points.first, first.isFinite else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            guard point.isFinite else { return nil }
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        self.init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var isFinite: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
    }

    func contains(_ point: Point2D) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    func union(_ other: Bounds) -> Bounds {
        Bounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}

struct AffineTransform2D: Equatable, Sendable {
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var tx: Double
    var ty: Double

    static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    static func translation(x: Double, y: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    static func scale(x: Double, y: Double) -> AffineTransform2D {
        AffineTransform2D(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    func applying(to point: Point2D) -> Point2D {
        Point2D(
            x: a * point.x + c * point.y + tx,
            y: b * point.x + d * point.y + ty
        )
    }

    /// Returns a transform that applies `self` first and `next` second.
    func followed(by next: AffineTransform2D) -> AffineTransform2D {
        AffineTransform2D(
            a: next.a * a + next.c * b,
            b: next.b * a + next.d * b,
            c: next.a * c + next.c * d,
            d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx,
            ty: next.b * tx + next.d * ty + next.ty
        )
    }

    func inverted(epsilon: Double = 1e-12) -> AffineTransform2D? {
        let determinant = a * d - b * c
        guard determinant.isFinite, abs(determinant) > epsilon else { return nil }
        let inverseA = d / determinant
        let inverseB = -b / determinant
        let inverseC = -c / determinant
        let inverseD = a / determinant
        return AffineTransform2D(
            a: inverseA,
            b: inverseB,
            c: inverseC,
            d: inverseD,
            tx: -(inverseA * tx + inverseC * ty),
            ty: -(inverseB * tx + inverseD * ty)
        )
    }
}

struct CubicBezier: Equatable, Sendable {
    var start: Point2D
    var control1: Point2D
    var control2: Point2D
    var end: Point2D

    var isFinite: Bool {
        start.isFinite && control1.isFinite && control2.isFinite && end.isFinite
    }

    func point(at t: Double) -> Point2D {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        return Point2D(
            x: mt2 * mt * start.x
                + 3 * mt2 * t * control1.x
                + 3 * mt * t2 * control2.x
                + t2 * t * end.x,
            y: mt2 * mt * start.y
                + 3 * mt2 * t * control1.y
                + 3 * mt * t2 * control2.y
                + t2 * t * end.y
        )
    }

    func derivative(at t: Double) -> Vector2D {
        let mt = 1 - t
        let first = (control1 - start) * (3 * mt * mt)
        let second = (control2 - control1) * (6 * mt * t)
        let third = (end - control2) * (3 * t * t)
        return first + second + third
    }

    func split(at t: Double) -> (CubicBezier, CubicBezier) {
        let p01 = start.interpolated(to: control1, t: t)
        let p12 = control1.interpolated(to: control2, t: t)
        let p23 = control2.interpolated(to: end, t: t)
        let p012 = p01.interpolated(to: p12, t: t)
        let p123 = p12.interpolated(to: p23, t: t)
        let midpoint = p012.interpolated(to: p123, t: t)
        return (
            CubicBezier(start: start, control1: p01, control2: p012, end: midpoint),
            CubicBezier(start: midpoint, control1: p123, control2: p23, end: end)
        )
    }

    var bounds: Bounds {
        var points = [start, end]
        let xRoots = derivativeRoots(start.x, control1.x, control2.x, end.x)
        let yRoots = derivativeRoots(start.y, control1.y, control2.y, end.y)
        for t in xRoots + yRoots where t > 0 && t < 1 {
            points.append(point(at: t))
        }
        return Bounds(points: points)!
    }

    private func derivativeRoots(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
        let a = -p0 + 3 * p1 - 3 * p2 + p3
        let b = 2 * (p0 - 2 * p1 + p2)
        let c = p1 - p0
        if abs(a) < 1e-14 {
            guard abs(b) >= 1e-14 else { return [] }
            return [-c / b]
        }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        if discriminant == 0 {
            return [-b / (2 * a)]
        }
        let root = sqrt(discriminant)
        return [(-b + root) / (2 * a), (-b - root) / (2 * a)]
    }
}

enum Winding: Equatable, Sendable {
    case clockwise
    case counterClockwise
    case degenerate
}

func signedArea<C: Collection>(of points: C) -> Double where C.Element == Point2D {
    let values = Array(points)
    guard values.count >= 3 else { return 0 }
    var twiceArea = 0.0
    for index in values.indices {
        let next = values[(index + 1) % values.count]
        twiceArea += values[index].x * next.y - next.x * values[index].y
    }
    return twiceArea / 2
}

func winding<C: Collection>(of points: C, epsilon: Double = 1e-12) -> Winding
where C.Element == Point2D {
    let area = signedArea(of: points)
    guard area.isFinite, abs(area) > epsilon else { return .degenerate }
    return area > 0 ? .counterClockwise : .clockwise
}
