// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum FittingFinish {
    private static let harmonizeMaximumShift = 2.0
    private static let handleReachMaximum = 0.9

    static func mergeCollinearLines(_ input: FittedContour) -> FittedContour {
        var contour = input
        while contour.segments.count >= 3 {
            let count = contour.segments.count
            var mergeIndex: Int?
            for index in 0..<count {
                let previous = (index + count - 1) % count
                guard contour.isLine[previous], contour.isLine[index], contour.jointKinds[index] != .corner else {
                    continue
                }
                let start = contour.segments[previous].start
                let joint = contour.segments[index].start
                let end = contour.segments[index].end
                let chord = end - start
                let length = chord.magnitude
                guard length >= 1e-9 else { continue }
                let deviation = abs(chord.cross(joint - start) / length)
                if deviation <= FittingConstants.shortStraightMaximumDeviation {
                    mergeIndex = index
                    break
                }
            }
            guard let index = mergeIndex else { break }
            let previous = (index + contour.segments.count - 1) % contour.segments.count
            contour.segments[previous] = lineCubic(
                from: contour.segments[previous].start,
                to: contour.segments[index].end
            )
            contour.segments.remove(at: index)
            contour.isLine.remove(at: index)
            contour.jointKinds.remove(at: index)
        }
        return contour
    }

    static func collapseCornerSlivers(_ contour: FittedContour) -> FittedContour {
        let count = contour.segments.count
        guard count >= 3 else { return contour }
        var skip = Array(repeating: false, count: count)
        var replacementEnds = Array<Point2D?>(repeating: nil, count: count)
        for index in 0..<count {
            let previous = (index + count - 1) % count
            let next = (index + 1) % count
            guard !contour.isLine[index], contour.isLine[previous], contour.isLine[next] else { continue }
            let chord = contour.segments[index].start.distance(to: contour.segments[index].end)
            guard chord <= FittingConstants.cornerSliverMaximumChord,
                  let intersection = lineIntersection(
                    contour.segments[previous].start,
                    contour.segments[previous].end,
                    contour.segments[next].end,
                    contour.segments[next].start
                  )
            else { continue }
            let midpoint = contour.segments[index].start.interpolated(
                to: contour.segments[index].end,
                t: 0.5
            )
            guard intersection.distance(to: midpoint) <= FittingConstants.cornerSliverMaximumReach else {
                continue
            }
            skip[index] = true
            replacementEnds[previous] = intersection
        }

        var segments: [CubicBezier] = []
        var lineFlags: [Bool] = []
        var jointKinds: [SplitKind] = []
        for index in 0..<count where !skip[index] {
            var segment = contour.segments[index]
            if let replacement = replacementEnds[index] {
                segment = lineCubic(from: segment.start, to: replacement)
            }
            let previous = (index + count - 1) % count
            if skip[previous], let replacement = replacementEnds[(previous + count - 1) % count] {
                if contour.isLine[index] {
                    segment = lineCubic(from: replacement, to: segment.end)
                } else {
                    segment.start = replacement
                }
            }
            segments.append(segment)
            lineFlags.append(contour.isLine[index])
            jointKinds.append(skip[previous] ? .corner : contour.jointKinds[index])
        }
        return FittedContour(segments: segments, isLine: lineFlags, jointKinds: jointKinds)
    }

    static func collapseMicroLines(_ input: FittedContour) -> FittedContour {
        var contour = input
        let maximumTurn = FittingConstants.microLineMaximumTurnDegrees * .pi / 180
        while contour.segments.count >= 3 {
            let count = contour.segments.count
            var collapseIndex: Int?
            for index in 0..<count {
                let previous = (index + count - 1) % count
                let next = (index + 1) % count
                guard contour.isLine[index], !contour.isLine[previous], !contour.isLine[next] else {
                    continue
                }
                guard contour.segments[index].start.distance(to: contour.segments[index].end)
                    <= FittingConstants.microLineMaximumChord
                else { continue }
                let incoming = contour.segments[previous].end - contour.segments[previous].control2
                let outgoing = contour.segments[next].control1 - contour.segments[next].start
                guard incoming.magnitude >= 1e-9, outgoing.magnitude >= 1e-9 else { continue }
                if abs(atan2(incoming.cross(outgoing), incoming.dot(outgoing))) <= maximumTurn {
                    collapseIndex = index
                    break
                }
            }
            guard let index = collapseIndex else { break }
            let previous = (index + count - 1) % count
            let next = (index + 1) % count
            let weld = contour.segments[index].start.interpolated(to: contour.segments[index].end, t: 0.5)
            contour.segments[previous].end = weld
            contour.segments[next].start = weld
            contour.segments.remove(at: index)
            contour.isLine.remove(at: index)
            contour.jointKinds.remove(at: index)
        }
        return contour
    }

    static func tameShortCubicHandles(_ input: FittedContour) -> FittedContour {
        var contour = input
        for index in contour.segments.indices where !contour.isLine[index] {
            let chord = contour.segments[index].start.distance(to: contour.segments[index].end)
            guard chord <= FittingConstants.shortCubicMaximumChord else { continue }
            let maximumLength = chord * FittingConstants.shortCubicMaximumHandleFraction
            let first = contour.segments[index].control1 - contour.segments[index].start
            if first.magnitude > maximumLength {
                contour.segments[index].control1 = contour.segments[index].start
                    + first * (maximumLength / first.magnitude)
            }
            let second = contour.segments[index].control2 - contour.segments[index].end
            if second.magnitude > maximumLength {
                contour.segments[index].control2 = contour.segments[index].end
                    + second * (maximumLength / second.magnitude)
            }
        }
        return contour
    }

    static func smoothJoins(_ input: FittedContour) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        let maximumAngle = FittingConstants.smoothJoinMaximumDegrees * .pi / 180
        for index in 0..<count {
            let previous = (index + count - 1) % count
            let kind = contour.jointKinds[index]
            guard kind != .corner else { continue }
            let joint = contour.segments[index].start
            let incoming = joint - contour.segments[previous].control2
            let outgoing = contour.segments[index].control1 - joint
            guard incoming.magnitude >= 1e-9, outgoing.magnitude >= 1e-9,
                  angleBetween(incoming, outgoing) <= maximumAngle
            else { continue }

            var direction: Vector2D
            switch kind {
            case .extremumX:
                direction = Vector2D(dx: 0, dy: outgoing.dy >= 0 ? 1 : -1)
            case .extremumY:
                direction = Vector2D(dx: outgoing.dx >= 0 ? 1 : -1, dy: 0)
            default:
                guard let first = incoming.normalized(), let second = outgoing.normalized(),
                      let sum = (first + second).normalized()
                else { continue }
                direction = sum
            }
            if contour.isLine[previous] && contour.isLine[index] { continue }
            if contour.isLine[previous] {
                direction = incoming.normalized()!
            } else if contour.isLine[index] {
                direction = outgoing.normalized()!
            }
            if !contour.isLine[previous] {
                contour.segments[previous].control2 = joint + (-direction * incoming.magnitude)
            }
            if !contour.isLine[index] {
                contour.segments[index].control1 = joint + direction * outgoing.magnitude
            }
        }
        return contour
    }

    static func harmonize(_ input: FittedContour) -> FittedContour {
        var contour = input
        let count = contour.segments.count
        for _ in 0..<2 {
            for index in 0..<count {
                let previous = (index + count - 1) % count
                guard contour.jointKinds[index] != .corner,
                      !contour.isLine[previous], !contour.isLine[index]
                else { continue }
                let firstFar = contour.segments[previous].control1
                let firstNear = contour.segments[previous].control2
                let joint = contour.segments[index].start
                let secondNear = contour.segments[index].control1
                let secondFar = contour.segments[index].control2
                let joinDirection = secondNear - firstNear
                guard joinDirection.magnitude >= 1e-9 else { continue }
                let firstSide = joinDirection.cross(firstFar - firstNear)
                let secondSide = joinDirection.cross(secondFar - secondNear)
                guard firstSide * secondSide > 0,
                      let intersection = lineIntersection(firstFar, firstNear, secondNear, secondFar)
                else { continue }
                let firstLength = firstFar.distance(to: firstNear)
                let firstToIntersection = firstNear.distance(to: intersection)
                let intersectionToSecond = intersection.distance(to: secondNear)
                let secondLength = secondNear.distance(to: secondFar)
                guard firstToIntersection >= 1e-9, secondLength >= 1e-9 else { continue }
                let firstRatio = firstLength / firstToIntersection
                let secondRatio = intersectionToSecond / secondLength
                guard firstRatio.isFinite, secondRatio.isFinite, firstRatio > 0, secondRatio > 0 else {
                    continue
                }
                let ratio = sqrt(firstRatio * secondRatio)
                let parameter = ratio / (ratio + 1)
                let target = firstNear.interpolated(to: secondNear, t: parameter)
                var shift = target - joint
                if shift.magnitude > harmonizeMaximumShift {
                    shift = shift * (harmonizeMaximumShift / shift.magnitude)
                }
                let moved = joint + shift
                contour.segments[previous].end = moved
                contour.segments[index].start = moved
            }
        }
        return contour
    }

    static func capHandleReach(_ input: FittedContour) -> FittedContour {
        var contour = input
        for index in contour.segments.indices where !contour.isLine[index] {
            var segment = contour.segments[index]
            let chordVector = segment.end - segment.start
            let chord = chordVector.magnitude
            guard chord >= 1e-9 else { continue }
            var firstHandle = segment.control1 - segment.start
            var secondHandle = segment.control2 - segment.end
            let firstLength = firstHandle.magnitude
            let secondLength = secondHandle.magnitude
            if firstLength > 1e-9, secondLength > 1e-9,
               let triangle = ContourRefiner.handleTriangle(
                start: segment.start,
                startDirection: firstHandle / firstLength,
                end: segment.end,
                endDirection: secondHandle / secondLength
               )
            {
                if firstLength > triangle.0 {
                    segment.control1 = segment.start + firstHandle * (triangle.0 / firstLength)
                }
                if secondLength > triangle.1 {
                    segment.control2 = segment.end + secondHandle * (triangle.1 / secondLength)
                }
                firstHandle = segment.control1 - segment.start
                secondHandle = segment.control2 - segment.end
            }
            let chordDirection = chordVector / chord
            let reach = firstHandle.dot(chordDirection) - secondHandle.dot(chordDirection)
            let limit = chord * handleReachMaximum
            if reach > limit {
                let scale = limit / reach
                segment.control1 = segment.start + firstHandle * scale
                segment.control2 = segment.end + secondHandle * scale
            }
            contour.segments[index] = segment
        }
        return contour
    }
}
