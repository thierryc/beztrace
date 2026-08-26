// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import XCTest
@testable import BezierTraceCore

final class GeometryPropertyTests: XCTestCase {
    func testSeededAffineRoundTripsRemainFinite() throws {
        var random = SplitMix64(seed: 0xB37A_CE50_2026_0001)
        for _ in 0..<10_000 {
            let sx = random.double(in: 0.05...12)
            let sy = random.double(in: 0.05...12)
            let transform = AffineTransform2D.scale(x: sx, y: sy).followed(
                by: .translation(
                    x: random.double(in: -10_000...10_000),
                    y: random.double(in: -10_000...10_000)
                )
            )
            let point = Point2D(
                x: random.double(in: -10_000...10_000),
                y: random.double(in: -10_000...10_000)
            )
            let mapped = transform.applying(to: point)
            let restored = try XCTUnwrap(transform.inverted()).applying(to: mapped)
            XCTAssertTrue(mapped.isFinite)
            XCTAssertEqual(restored.x, point.x, accuracy: 1e-9)
            XCTAssertEqual(restored.y, point.y, accuracy: 1e-9)
        }
    }

    func testSeededCubicSplitsAreContinuousAndBoundsContainSamples() {
        var random = SplitMix64(seed: 0xB37A_CE50_2026_0002)
        for _ in 0..<5_000 {
            let points = (0..<4).map { _ in
                Point2D(
                    x: random.double(in: -2_048...2_048),
                    y: random.double(in: -2_048...2_048)
                )
            }
            let cubic = CubicBezier(
                start: points[0], control1: points[1], control2: points[2], end: points[3]
            )
            let parameter = random.double(in: 0...1)
            let halves = cubic.split(at: parameter)
            XCTAssertEqual(halves.0.end, halves.1.start)
            let evaluated = cubic.point(at: parameter)
            XCTAssertEqual(halves.0.end.x, evaluated.x, accuracy: 1e-9)
            XCTAssertEqual(halves.0.end.y, evaluated.y, accuracy: 1e-9)
            for sample in 0...32 {
                let point = cubic.point(at: Double(sample) / 32)
                XCTAssertTrue(cubic.bounds.contains(point, tolerance: 1e-9))
            }
        }
    }

    func testSeededPointOrderingIsStableAndTotalForFiniteValues() {
        var random = SplitMix64(seed: 0xB37A_CE50_2026_0003)
        let points = (0..<20_000).map { _ in
            Point2D(
                x: random.double(in: -1_000_000...1_000_000),
                y: random.double(in: -1_000_000...1_000_000)
            )
        }
        let first = points.sorted(by: Point2D.deterministicLessThan)
        let second = points.sorted(by: Point2D.deterministicLessThan)
        XCTAssertEqual(first, second)
        for pair in zip(first, first.dropFirst()) {
            XCTAssertFalse(Point2D.deterministicLessThan(pair.1, pair.0))
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private extension Bounds {
    func contains(_ point: Point2D, tolerance: Double) -> Bool {
        point.x >= minX - tolerance && point.x <= maxX + tolerance
            && point.y >= minY - tolerance && point.y <= maxY + tolerance
    }
}
