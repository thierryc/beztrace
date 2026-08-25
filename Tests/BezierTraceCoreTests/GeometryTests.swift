// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import XCTest
@testable import BezierTraceCore

final class GeometryTests: XCTestCase {
    func testPointVectorArithmeticAndDistance() {
        let point = Point2D(x: 2, y: 3)
        let vector = Vector2D(dx: 5, dy: -1)

        XCTAssertEqual(point + vector, Point2D(x: 7, y: 2))
        XCTAssertEqual((point + vector) - point, vector)
        XCTAssertEqual(point.distance(to: Point2D(x: 5, y: 7)), 5, accuracy: 1e-12)
        XCTAssertEqual(point.interpolated(to: Point2D(x: 6, y: 11), t: 0.25), Point2D(x: 3, y: 5))
    }

    func testVectorProductsAndNormalization() throws {
        let a = Vector2D(dx: 3, dy: 4)
        let b = Vector2D(dx: -2, dy: 5)

        XCTAssertEqual(a.magnitude, 5, accuracy: 1e-12)
        XCTAssertEqual(a.dot(b), 14, accuracy: 1e-12)
        XCTAssertEqual(a.cross(b), 23, accuracy: 1e-12)
        let normalized = try XCTUnwrap(a.normalized())
        XCTAssertEqual(normalized.dx, 0.6, accuracy: 1e-12)
        XCTAssertEqual(normalized.dy, 0.8, accuracy: 1e-12)
        XCTAssertNil(Vector2D.zero.normalized())
    }

    func testBoundsUnionAndContainment() throws {
        let bounds = try XCTUnwrap(Bounds(points: [
            Point2D(x: 4, y: -2),
            Point2D(x: -3, y: 8),
            Point2D(x: 1, y: 5),
        ]))

        XCTAssertEqual(bounds, Bounds(minX: -3, minY: -2, maxX: 4, maxY: 8))
        XCTAssertEqual(bounds.width, 7)
        XCTAssertEqual(bounds.height, 10)
        XCTAssertTrue(bounds.contains(Point2D(x: 0, y: 0)))
        XCTAssertFalse(bounds.contains(Point2D(x: 5, y: 0)))
        XCTAssertEqual(
            bounds.union(Bounds(minX: -10, minY: 3, maxX: -8, maxY: 12)),
            Bounds(minX: -10, minY: -2, maxX: 4, maxY: 12)
        )
        XCTAssertNil(Bounds(points: []))
    }

    func testAffineCompositionAndInverse() throws {
        let transform = AffineTransform2D.scale(x: 2, y: 3)
            .followed(by: .translation(x: 10, y: -4))
        let point = Point2D(x: 7, y: 5)
        let transformed = transform.applying(to: point)

        XCTAssertEqual(transformed, Point2D(x: 24, y: 11))
        let inverse = try XCTUnwrap(transform.inverted())
        XCTAssertEqual(inverse.applying(to: transformed).x, point.x, accuracy: 1e-12)
        XCTAssertEqual(inverse.applying(to: transformed).y, point.y, accuracy: 1e-12)
        XCTAssertNil(AffineTransform2D.scale(x: 0, y: 1).inverted())
    }

    func testCubicEvaluationDerivativeSplitAndBounds() {
        let curve = CubicBezier(
            start: Point2D(x: 0, y: 0),
            control1: Point2D(x: 0, y: 10),
            control2: Point2D(x: 10, y: 10),
            end: Point2D(x: 10, y: 0)
        )

        XCTAssertEqual(curve.point(at: 0.5), Point2D(x: 5, y: 7.5))
        XCTAssertEqual(curve.derivative(at: 0), Vector2D(dx: 0, dy: 30))
        XCTAssertEqual(curve.derivative(at: 1), Vector2D(dx: 0, dy: -30))
        let halves = curve.split(at: 0.5)
        XCTAssertEqual(halves.0.end, curve.point(at: 0.5))
        XCTAssertEqual(halves.1.start, curve.point(at: 0.5))
        XCTAssertEqual(curve.bounds, Bounds(minX: 0, minY: 0, maxX: 10, maxY: 7.5))
    }

    func testSignedAreaAndWinding() {
        let counterClockwise = [
            Point2D(x: 0, y: 0),
            Point2D(x: 10, y: 0),
            Point2D(x: 10, y: 10),
            Point2D(x: 0, y: 10),
        ]

        XCTAssertEqual(signedArea(of: counterClockwise), 100)
        XCTAssertEqual(winding(of: counterClockwise), .counterClockwise)
        XCTAssertEqual(winding(of: counterClockwise.reversed()), .clockwise)
        XCTAssertEqual(winding(of: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)]), .degenerate)
    }

    func testFiniteAndDeterministicPointOrdering() {
        XCTAssertTrue(Point2D(x: 1, y: 2).isFinite)
        XCTAssertFalse(Point2D(x: .infinity, y: 2).isFinite)
        XCTAssertEqual(
            [Point2D(x: 2, y: 0), Point2D(x: 1, y: 5), Point2D(x: 1, y: -2)]
                .sorted(by: Point2D.deterministicLessThan),
            [Point2D(x: 1, y: -2), Point2D(x: 1, y: 5), Point2D(x: 2, y: 0)]
        )
    }
}
