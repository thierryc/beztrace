// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum InternalPathElement: Equatable, Sendable {
    case move(Point2D)
    case line(Point2D)
    case curve(control1: Point2D, control2: Point2D, end: Point2D)
    case close
}

struct FittedContour: Equatable, Sendable {
    var segments: [CubicBezier]
    var isLine: [Bool]
    /// Kind of the joint at the start of each segment.
    var jointKinds: [SplitKind]

    init(segments: [CubicBezier], isLine: [Bool], jointKinds: [SplitKind]) {
        precondition(segments.count == isLine.count && segments.count == jointKinds.count)
        self.segments = segments
        self.isLine = isLine
        self.jointKinds = jointKinds
    }

    var pathElements: [InternalPathElement] {
        guard let first = segments.first else { return [] }
        var result: [InternalPathElement] = [.move(first.start)]
        result.reserveCapacity(segments.count + 2)
        for (index, segment) in segments.enumerated() {
            if isLine[index] {
                result.append(.line(segment.end))
            } else {
                result.append(.curve(
                    control1: segment.control1,
                    control2: segment.control2,
                    end: segment.end
                ))
            }
        }
        result.append(.close)
        return result
    }

    func scaled(by factor: Double) -> FittedContour {
        func scale(_ point: Point2D) -> Point2D {
            Point2D(x: point.x * factor, y: point.y * factor)
        }
        return FittedContour(
            segments: segments.map {
                CubicBezier(
                    start: scale($0.start),
                    control1: scale($0.control1),
                    control2: scale($0.control2),
                    end: scale($0.end)
                )
            },
            isLine: isLine,
            jointKinds: jointKinds
        )
    }
}

struct PathSegment: Equatable, Sendable {
    var cubic: CubicBezier
    var isLine: Bool
}

struct BezierPathContour: Equatable, Sendable {
    var segments: [PathSegment]

    init(segments: [PathSegment]) {
        self.segments = segments
    }

    init(_ fitted: FittedContour) {
        segments = fitted.segments.indices.map {
            PathSegment(cubic: fitted.segments[$0], isLine: fitted.isLine[$0])
        }
    }

    var pathElements: [InternalPathElement] {
        guard let first = segments.first else { return [] }
        var result: [InternalPathElement] = [.move(first.cubic.start)]
        for segment in segments {
            if segment.isLine {
                result.append(.line(segment.cubic.end))
            } else {
                result.append(.curve(
                    control1: segment.cubic.control1,
                    control2: segment.cubic.control2,
                    end: segment.cubic.end
                ))
            }
        }
        result.append(.close)
        return result
    }
}

struct CubicFitResult: Equatable, Sendable {
    let curve: CubicBezier
    let maximumError: Double
}

enum FittingConstants {
    static let constrainedFitToleranceFactor = 1.8
    static let freeDirectionAxisSnapDegrees = 15.0
    static let cornerAxisSnapDegrees = 12.0
    static let cornerSliverMaximumChord = 32.0
    static let cornerSliverMaximumReach = 15.0
    static let shortCubicMaximumChord = 15.0
    static let shortCubicMaximumHandleFraction = 0.45
    static let shortStraightMaximumSamples = 16
    static let openFitMaximumSegments = 24
    static let shortStraightMaximumDeviation = 1.2
    static let microLineMaximumChord = 14.0
    static let microLineMaximumTurnDegrees = 25.0
    static let smoothJoinMaximumDegrees = 30.0
}

func lineCubic(from start: Point2D, to end: Point2D) -> CubicBezier {
    CubicBezier(
        start: start,
        control1: start.interpolated(to: end, t: 1.0 / 3.0),
        control2: start.interpolated(to: end, t: 2.0 / 3.0),
        end: end
    )
}

func chordDeviation(_ points: ArraySlice<Point2D>) -> Double {
    guard points.count >= 3, let first = points.first, let last = points.last else { return 0 }
    let chord = last - first
    let length = chord.magnitude
    guard length >= 1e-12 else { return 0 }
    return points.dropFirst().dropLast().reduce(0) { maximum, point in
        max(maximum, abs((point - first).cross(chord)) / length)
    }
}

func chordDeviation(_ points: [Point2D]) -> Double {
    chordDeviation(points[...])
}

func lineIntersection(_ a1: Point2D, _ a2: Point2D, _ b1: Point2D, _ b2: Point2D) -> Point2D? {
    let firstDirection = a2 - a1
    let secondDirection = b2 - b1
    let denominator = firstDirection.cross(secondDirection)
    guard abs(denominator) >= 1e-9 else { return nil }
    let t = (b1 - a1).cross(secondDirection) / denominator
    return a1 + firstDirection * t
}

func angleBetween(_ first: Vector2D, _ second: Vector2D) -> Double {
    abs(atan2(first.cross(second), first.dot(second)))
}
