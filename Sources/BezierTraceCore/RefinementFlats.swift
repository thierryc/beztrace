// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

enum RefinementFlats {
    private static let clusterMaximumLength = 26.0
    private static let wallMinimumChord = 8.0
    private static let minimumTurnDegrees = 50.0
    private static let axisToleranceDegrees = 35.0
    private static let minimumWidthUnits = 2.0
    private static let maximumWidthUnits = 12.0
    private static let narrowTieFactor = 1.08
    private static let wallNearLength = 30.0
    private static let deepSlack = 40.0
    private static let shallowSlack = 12.0
    private static let minimumBaseLoss = 0.003
    private static let acceptanceFactor = 0.8
    private static let absoluteMaximumLoss = 0.03
    private static let maximumTiltDegrees = 3.0
    private static let tiltFloor = 3.0
    private static let searchSteps = 24

    static func junctionFlats(
        _ input: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool
    ) -> FittedContour {
        var contour = input
        while contour.segments.count >= 6 {
            let polylines = ContourRefiner.allPolylines(contour)
            var best: (contour: FittedContour, priority: Int, ratio: Double)?
            for index in contour.segments.indices {
                for clusterCount in 0...2 {
                    guard let candidate = tryFlat(
                        contour,
                        raster: raster,
                        inkLeft: inkLeft,
                        startIndex: index,
                        clusterCount: clusterCount,
                        polylines: polylines
                    ) else { continue }
                    let priority = 1 - clusterCount
                    if best == nil
                        || priority < best!.priority
                        || priority == best!.priority && candidate.ratio < best!.ratio
                    {
                        best = (candidate.contour, priority, candidate.ratio)
                    }
                }
            }
            guard let best else { break }
            contour = best.contour
        }
        return contour
    }

    private static func tryFlat(
        _ contour: FittedContour,
        raster: RasterTarget,
        inkLeft: Bool,
        startIndex: Int,
        clusterCount: Int,
        polylines: [[Point2D]]
    ) -> (contour: FittedContour, ratio: Double)? {
        let count = contour.segments.count
        guard count >= clusterCount + 4 else { return nil }
        let incomingWall = (startIndex + count - 1) % count
        let outgoingWall = (startIndex + clusterCount) % count
        func isInCluster(_ index: Int) -> Bool {
            (0..<clusterCount).contains { (startIndex + $0) % count == index }
        }

        if clusterCount > 0 {
            let length = (0..<clusterCount).reduce(0) {
                $0 + contour.segments[(startIndex + $1) % count].start.distance(
                    to: contour.segments[(startIndex + $1) % count].end
                )
            }
            guard length <= clusterMaximumLength else { return nil }
            if clusterCount == 1, contour.isLine[startIndex] {
                let direction = contour.segments[startIndex].end - contour.segments[startIndex].start
                if abs(direction.dx) < 1e-6 || abs(direction.dy) < 1e-6 { return nil }
            }
        }
        for wall in [incomingWall, outgoingWall] {
            guard contour.segments[wall].start.distance(to: contour.segments[wall].end)
                >= wallMinimumChord
            else { return nil }
        }
        guard let incomingSecant = approachDirection(polylines[incomingWall], atStart: false),
              let outgoingSecant = approachDirection(polylines[outgoingWall], atStart: true)
        else { return nil }
        let turn = acos(min(max(incomingSecant.dot(outgoingSecant), -1), 1))
        guard turn >= minimumTurnDegrees * .pi / 180 else { return nil }
        let cross = incomingSecant.cross(outgoingSecant)
        guard inkLeft ? cross < 0 : cross > 0 else { return nil }

        let measuredDepth = incomingSecant - outgoingSecant
        guard let measuredDepthDirection = measuredDepth.normalized(), measuredDepth.magnitude >= 0.2 else {
            return nil
        }
        let depth: Vector2D
        if abs(measuredDepthDirection.dx) >= abs(measuredDepthDirection.dy) {
            depth = Vector2D(dx: numericSign(measuredDepthDirection.dx), dy: 0)
        } else {
            depth = Vector2D(dx: 0, dy: numericSign(measuredDepthDirection.dy))
        }
        guard measuredDepthDirection.dot(depth) >= cos(axisToleranceDegrees * .pi / 180) else {
            return nil
        }
        func depthValue(_ point: Point2D) -> Double { point.x * depth.dx + point.y * depth.dy }
        func tangent(_ segment: CubicBezier, isLine: Bool, atStart: Bool) -> Vector2D? {
            let vector = isLine
                ? segment.end - segment.start
                : atStart ? segment.control1 - segment.start : segment.end - segment.control2
            return vector.normalized()
        }
        let incomingTangent = tangent(
            contour.segments[incomingWall],
            isLine: contour.isLine[incomingWall],
            atStart: false
        )
        let incomingDirection = incomingTangent.map {
            $0.dot(depth) > incomingSecant.dot(depth) ? $0 : incomingSecant
        } ?? incomingSecant
        let outgoingTangent = tangent(
            contour.segments[outgoingWall],
            isLine: contour.isLine[outgoingWall],
            atStart: true
        )
        let outgoingDirection = outgoingTangent.map {
            $0.dot(depth) < outgoingSecant.dot(depth) ? $0 : outgoingSecant
        } ?? outgoingSecant
        guard incomingDirection.dot(depth) >= 0.05,
              outgoingDirection.dot(depth) <= -0.05
        else { return nil }

        let projectedIncoming = incomingSecant - depth * incomingSecant.dot(depth)
        let projectedOutgoing = outgoingSecant - depth * outgoingSecant.dot(depth)
        guard let tangentDirection = (projectedIncoming + projectedOutgoing).normalized() else { return nil }
        let incomingAnchor = contour.segments[incomingWall].end
        let outgoingAnchor = contour.segments[outgoingWall].start
        let cluster: [Point2D]
        if clusterCount == 0 {
            cluster = [contour.segments[startIndex].start]
        } else {
            cluster = (0..<clusterCount).flatMap { polylines[(startIndex + $0) % count] }
        }
        let deepestValue = cluster.reduce(max(depthValue(incomingAnchor), depthValue(outgoingAnchor))) {
            max($0, depthValue($1))
        }
        let deepest = cluster.max { depthValue($0) < depthValue($1) } ?? incomingAnchor
        let interiorPoint = deepest + (-depth * 4)
        let interiorCoverage = raster.coverage(x: interiorPoint.x, yUp: interiorPoint.y)
        var reach = deepSlack
        var search = -4.0
        while search < deepSlack {
            search += 1
            let point = deepest + depth * search
            if abs(raster.coverage(x: point.x, yUp: point.y) - interiorCoverage) > 0.5 {
                reach = max(search + 3, 4)
                break
            }
        }

        let sharpVertex = clusterCount > 0
            ? ContourRefiner.rayIntersection(
                start: incomingAnchor,
                direction: incomingDirection,
                otherStart: outgoingAnchor,
                otherDirection: -outgoingDirection
            )
            : nil
        let deepLimit = sharpVertex.map {
            min(depthValue($0) + 1, deepestValue + reach)
        } ?? deepestValue + reach
        let shallowLimit = deepestValue - shallowSlack
        guard deepLimit > shallowLimit else { return nil }

        let incomingSplit = splitWallNear(polylines[incomingWall], nearIsStart: false)
        let outgoingSplit = splitWallNear(polylines[outgoingWall], nearIsStart: true)
        let incomingNear = densify(incomingSplit.near)
        let outgoingNear = densify(outgoingSplit.near)
        let incomingExtension = rayPoints(
            from: incomingAnchor,
            direction: incomingDirection,
            length: max(deepLimit - depthValue(incomingAnchor), 0) + 2
        )
        let outgoingExtension = rayPoints(
            from: outgoingAnchor,
            direction: -outgoingDirection,
            length: max(deepLimit - depthValue(outgoingAnchor), 0) + 2
        )
        var region = incomingNear + cluster + outgoingNear + incomingExtension + outgoingExtension
        for offset in [-6.0, 0.0, 6.0] {
            region += rayPoints(
                from: deepest + tangentDirection * offset,
                direction: depth,
                length: max(deepLimit - deepestValue, 0) + 2
            )
        }
        let fullBand = ContourRefiner.collectBand(
            raster: raster,
            region: region,
            fixed: [incomingSplit.rest, outgoingSplit.rest]
        )
        let center = incomingAnchor.interpolated(to: outgoingAnchor, t: 0.5)
        let tip = deepest + depth * max(deepLimit - deepestValue, 0)
        let judgeRadius = max(incomingAnchor.distance(to: center), tip.distance(to: center)) + 6
        let band = fullBand.filter { $0.point.distance(to: center) <= judgeRadius }
        guard band.count >= 16 else { return nil }
        let basePolyline = incomingNear + cluster + outgoingNear
        let baseLoss = ContourRefiner.bandLoss(band, candidate: basePolyline, inkLeft: inkLeft)
        guard baseLoss >= minimumBaseLoss else { return nil }

        let candidates: (sharpLoss: Double, flatLoss: Double, first: Point2D, second: Point2D)?
        if clusterCount == 0 {
            candidates = bareJointCandidates(
                contour: contour,
                index: startIndex,
                incomingWall: incomingWall,
                outgoingWall: outgoingWall,
                incomingAnchor: incomingAnchor,
                outgoingAnchor: outgoingAnchor,
                incomingNear: incomingNear,
                outgoingNear: outgoingNear,
                depth: depth,
                tangent: tangentDirection,
                depthValue: depthValue,
                shallowLimit: shallowLimit,
                deepLimit: deepLimit,
                band: band,
                inkLeft: inkLeft,
                pixelsPerUnit: raster.pixelsPerUnit
            )
        } else {
            candidates = clusterCandidates(
                sharpVertex: sharpVertex,
                incomingNear: incomingNear,
                outgoingNear: outgoingNear,
                incomingExtension: incomingExtension,
                outgoingExtension: outgoingExtension,
                depth: depth,
                tangent: tangentDirection,
                depthValue: depthValue,
                shallowLimit: shallowLimit,
                deepLimit: deepLimit,
                band: band,
                inkLeft: inkLeft,
                pixelsPerUnit: raster.pixelsPerUnit
            )
        }
        guard let candidates else { return nil }
        let incumbent = min(baseLoss, candidates.sharpLoss)
        guard candidates.flatLoss <= acceptanceFactor * incumbent,
              candidates.flatLoss <= absoluteMaximumLoss
        else { return nil }

        let rebuiltIncoming = reanchor(
            contour.segments[incomingWall],
            isLine: contour.isLine[incomingWall],
            endpoint: candidates.first,
            atStart: false
        )
        let rebuiltOutgoing = reanchor(
            contour.segments[outgoingWall],
            isLine: contour.isLine[outgoingWall],
            endpoint: candidates.second,
            atStart: true
        )
        let flat = lineCubic(from: candidates.first, to: candidates.second)
        var segments: [CubicBezier] = []
        var lineFlags: [Bool] = []
        var jointKinds: [SplitKind] = []
        segments.reserveCapacity(count + 1 - clusterCount)
        lineFlags.reserveCapacity(count + 1 - clusterCount)
        jointKinds.reserveCapacity(count + 1 - clusterCount)
        for index in 0..<count {
            if index == incomingWall {
                segments.append(rebuiltIncoming)
                lineFlags.append(contour.isLine[incomingWall])
                jointKinds.append(contour.jointKinds[incomingWall])
            } else if clusterCount == 0, index == startIndex {
                segments += [flat, rebuiltOutgoing]
                lineFlags += [true, contour.isLine[outgoingWall]]
                jointKinds += [.corner, .corner]
            } else if clusterCount > 0, index == startIndex {
                segments.append(flat)
                lineFlags.append(true)
                jointKinds.append(.corner)
            } else if clusterCount > 0, index == outgoingWall {
                segments.append(rebuiltOutgoing)
                lineFlags.append(contour.isLine[outgoingWall])
                jointKinds.append(.corner)
            } else if !isInCluster(index) {
                segments.append(contour.segments[index])
                lineFlags.append(contour.isLine[index])
                jointKinds.append(contour.jointKinds[index])
            }
        }
        return (
            FittedContour(segments: segments, isLine: lineFlags, jointKinds: jointKinds),
            candidates.flatLoss / max(incumbent, 1e-9)
        )
    }

    private static func bareJointCandidates(
        contour: FittedContour,
        index: Int,
        incomingWall: Int,
        outgoingWall: Int,
        incomingAnchor: Point2D,
        outgoingAnchor: Point2D,
        incomingNear: [Point2D],
        outgoingNear: [Point2D],
        depth: Vector2D,
        tangent: Vector2D,
        depthValue: (Point2D) -> Double,
        shallowLimit: Double,
        deepLimit: Double,
        band: [RefinementBandPoint],
        inkLeft: Bool,
        pixelsPerUnit: Double
    ) -> (sharpLoss: Double, flatLoss: Double, first: Point2D, second: Point2D)? {
        let vertex = contour.segments[index].start
        let farIncoming = contour.segments[incomingWall].start
        let farOutgoing = contour.segments[outgoingWall].end
        let maximumTilt = tan(maximumTiltDegrees * .pi / 180)
        func tiltAllowed(_ point: Point2D, far: Point2D, near: Point2D) -> Bool {
            let old = near - far
            let length = old.magnitude
            guard length >= 1e-9 else { return false }
            let perpendicular = abs((old / length).cross(point - far))
            return perpendicular <= max(length * maximumTilt, tiltFloor)
        }
        let originalDepth = depthValue(vertex)
        func evaluateSharp(_ offset: Double) -> Double {
            let moved = vertex + depth * offset
            guard tiltAllowed(moved, far: farIncoming, near: incomingAnchor),
                  tiltAllowed(moved, far: farOutgoing, near: outgoingAnchor)
            else { return .infinity }
            let polyline = shear(incomingNear, delta: moved - vertex, nearIsLast: true)
                + shear(outgoingNear, delta: moved - vertex, nearIsLast: false)
            return ContourRefiner.bandLoss(band, candidate: polyline, inkLeft: inkLeft)
        }
        let sharpOffset = ContourRefiner.goldenMinimum(
            low: shallowLimit - originalDepth,
            high: deepLimit - originalDepth,
            function: evaluateSharp
        )
        let sharpLoss = evaluateSharp(sharpOffset)
        func evaluateFlat(_ candidateDepth: Double, width: Double) -> Double {
            let center = vertex + depth * (candidateDepth - originalDepth)
            let first = center + (-tangent * (width * 0.5))
            let second = center + tangent * (width * 0.5)
            guard tiltAllowed(first, far: farIncoming, near: incomingAnchor),
                  tiltAllowed(second, far: farOutgoing, near: outgoingAnchor)
            else { return .infinity }
            let polyline = shear(incomingNear, delta: first - vertex, nearIsLast: true)
                + shear(outgoingNear, delta: second - vertex, nearIsLast: false)
            return ContourRefiner.bandLoss(band, candidate: polyline, inkLeft: inkLeft)
        }
        let widthUnits = [2.0, 3.0, 4.0, 5.0, 6.5, 8.0, 10.0, 12.0]
        let scaledWidths = widthUnits.map { $0 * pixelsPerUnit }
        var perWidth = Array(repeating: (loss: Double.infinity, depth: Double.nan), count: widthUnits.count)
        for (widthIndex, width) in scaledWidths.enumerated() {
            for step in 0...searchSteps {
                let candidateDepth = shallowLimit
                    + (deepLimit - shallowLimit) * Double(step) / Double(searchSteps)
                let loss = evaluateFlat(candidateDepth, width: width)
                if loss < perWidth[widthIndex].loss { perWidth[widthIndex] = (loss, candidateDepth) }
            }
        }
        let global = perWidth.map(\.loss).min() ?? .infinity
        guard global.isFinite,
              let widthIndex = perWidth.firstIndex(where: { $0.loss <= narrowTieFactor * global })
        else { return nil }
        // Preserve the pinned behavior: the coarse search uses scaled
        // widths, while the final refinement uses the selected font-unit
        // width directly.
        let width = widthUnits[widthIndex]
        let depthStep = (deepLimit - shallowLimit) / Double(searchSteps)
        let candidateDepth = ContourRefiner.goldenMinimum(
            low: max(perWidth[widthIndex].depth - depthStep, shallowLimit),
            high: min(perWidth[widthIndex].depth + depthStep, deepLimit)
        ) { evaluateFlat($0, width: width) }
        let flatLoss = evaluateFlat(candidateDepth, width: width)
        guard flatLoss.isFinite else { return nil }
        let center = vertex + depth * (candidateDepth - originalDepth)
        return (
            sharpLoss,
            flatLoss,
            center + (-tangent * (width * 0.5)),
            center + tangent * (width * 0.5)
        )
    }

    private static func clusterCandidates(
        sharpVertex: Point2D?,
        incomingNear: [Point2D],
        outgoingNear: [Point2D],
        incomingExtension: [Point2D],
        outgoingExtension: [Point2D],
        depth: Vector2D,
        tangent: Vector2D,
        depthValue: (Point2D) -> Double,
        shallowLimit: Double,
        deepLimit: Double,
        band: [RefinementBandPoint],
        inkLeft: Bool,
        pixelsPerUnit: Double
    ) -> (sharpLoss: Double, flatLoss: Double, first: Point2D, second: Point2D)? {
        let sharpLoss: Double
        if let sharpVertex {
            sharpLoss = ContourRefiner.bandLoss(
                band,
                candidate: incomingNear + [sharpVertex] + outgoingNear,
                inkLeft: inkLeft
            )
        } else {
            sharpLoss = .infinity
        }
        let incomingExtended = incomingNear + incomingExtension
        let outgoingExtended = Array(outgoingExtension.reversed()) + outgoingNear
        func evaluate(_ candidateDepth: Double) -> (Double, (Point2D, Point2D)?) {
            guard let first = crossAtDepth(
                incomingExtended,
                axis: depth,
                depth: candidateDepth,
                chooseLast: true
            ), let second = crossAtDepth(
                outgoingExtended,
                axis: depth,
                depth: candidateDepth,
                chooseLast: false
            ) else { return (.infinity, nil) }
            let width = first.distance(to: second)
            let minimumWidth = minimumWidthUnits * pixelsPerUnit
            let maximumWidth = maximumWidthUnits * pixelsPerUnit
            guard width >= minimumWidth, width <= maximumWidth,
                  (second - first).dot(tangent) >= minimumWidth * 0.5
            else { return (.infinity, nil) }
            let polyline = incomingNear.filter { depthValue($0) < candidateDepth }
                + [first, second]
                + outgoingNear.filter { depthValue($0) < candidateDepth }
            return (ContourRefiner.bandLoss(band, candidate: polyline, inkLeft: inkLeft), (first, second))
        }
        var bestDepth = Double.nan
        var bestLoss = Double.infinity
        for step in 0...searchSteps {
            let candidateDepth = shallowLimit
                + (deepLimit - shallowLimit) * Double(step) / Double(searchSteps)
            let loss = evaluate(candidateDepth).0
            if loss < bestLoss { bestLoss = loss; bestDepth = candidateDepth }
        }
        guard bestLoss.isFinite else { return nil }
        let depthStep = (deepLimit - shallowLimit) / Double(searchSteps)
        let candidateDepth = ContourRefiner.goldenMinimum(
            low: max(bestDepth - depthStep, shallowLimit),
            high: min(bestDepth + depthStep, deepLimit)
        ) { evaluate($0).0 }
        let evaluated = evaluate(candidateDepth)
        guard let endpoints = evaluated.1 else { return nil }
        return (sharpLoss, evaluated.0, endpoints.0, endpoints.1)
    }

    private static func approachDirection(_ polyline: [Point2D], atStart: Bool) -> Vector2D? {
        guard !polyline.isEmpty else { return nil }
        var forward = polyline
        if atStart { forward.reverse() }
        let near = forward[forward.count - 1]
        var accumulated = 0.0
        var far = forward[0]
        if forward.count >= 2 {
            for index in stride(from: forward.count - 2, through: 0, by: -1) {
                accumulated += forward[index + 1].distance(to: forward[index])
                if accumulated >= 8 { far = forward[index]; break }
            }
        }
        let vector = atStart ? far - near : near - far
        return vector.normalized()
    }

    private static func reanchor(
        _ segment: CubicBezier,
        isLine: Bool,
        endpoint: Point2D,
        atStart: Bool
    ) -> CubicBezier {
        if isLine {
            return atStart
                ? lineCubic(from: endpoint, to: segment.end)
                : lineCubic(from: segment.start, to: endpoint)
        }
        let start = atStart ? endpoint : segment.start
        let end = atStart ? segment.end : endpoint
        let firstHandle = segment.control1 - segment.start
        let secondHandle = segment.control2 - segment.end
        guard firstHandle.magnitude >= 1e-9, secondHandle.magnitude >= 1e-9 else {
            return lineCubic(from: start, to: end)
        }
        let scale = start.distance(to: end) / max(segment.start.distance(to: segment.end), 1e-9)
        return CubicBezier(
            start: start,
            control1: start + firstHandle * scale,
            control2: end + secondHandle * scale,
            end: end
        )
    }

    private static func splitWallNear(
        _ polyline: [Point2D],
        nearIsStart: Bool
    ) -> (near: [Point2D], rest: [Point2D]) {
        var forward = polyline
        if nearIsStart { forward.reverse() }
        var nearReversed = [forward[forward.count - 1]]
        var rest: [Point2D] = []
        var accumulated = 0.0
        if forward.count >= 2 {
            for index in stride(from: forward.count - 2, through: 0, by: -1) {
                let step = forward[index + 1].distance(to: forward[index])
                if accumulated + step <= wallNearLength {
                    nearReversed.append(forward[index])
                    accumulated += step
                } else {
                    let cut = forward[index + 1].interpolated(
                        to: forward[index],
                        t: (wallNearLength - accumulated) / max(step, 1e-9)
                    )
                    nearReversed.append(cut)
                    rest = Array(forward[...index])
                    rest.append(cut)
                    break
                }
            }
        }
        nearReversed.reverse()
        var near = nearReversed
        if nearIsStart { near.reverse(); rest.reverse() }
        return (near, rest)
    }

    private static func shear(
        _ polyline: [Point2D],
        delta: Vector2D,
        nearIsLast: Bool
    ) -> [Point2D] {
        let total = zip(polyline, polyline.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard total >= 1e-9 else { return polyline.map { $0 + delta } }
        var result: [Point2D] = []
        var accumulated = 0.0
        for index in polyline.indices {
            if index > 0 { accumulated += polyline[index].distance(to: polyline[index - 1]) }
            let fraction = nearIsLast ? accumulated / total : 1 - accumulated / total
            result.append(polyline[index] + delta * fraction)
        }
        return result
    }

    private static func densify(_ polyline: [Point2D]) -> [Point2D] {
        var result: [Point2D] = []
        for (first, second) in zip(polyline, polyline.dropFirst()) {
            result.append(first)
            let extra = Int(floor(first.distance(to: second) / 2))
            if extra > 0 {
                for index in 1...extra {
                    result.append(first.interpolated(to: second, t: Double(index) / Double(extra + 1)))
                }
            }
        }
        if let last = polyline.last { result.append(last) }
        return result
    }

    private static func rayPoints(
        from start: Point2D,
        direction: Vector2D,
        length: Double
    ) -> [Point2D] {
        let steps = max(Int(ceil(length / 2)), 1)
        return (1...steps).map { start + direction * min(Double($0) * 2, length) }
    }

    private static func crossAtDepth(
        _ polyline: [Point2D],
        axis: Vector2D,
        depth: Double,
        chooseLast: Bool
    ) -> Point2D? {
        func projection(_ point: Point2D) -> Double { point.x * axis.dx + point.y * axis.dy }
        var found: Point2D?
        guard polyline.count >= 2 else { return nil }
        for index in 0..<(polyline.count - 1) {
            let first = projection(polyline[index]) - depth
            let second = projection(polyline[index + 1]) - depth
            guard first * second <= 0 else { continue }
            let span = second - first
            guard abs(span) >= 1e-12 else { continue }
            found = polyline[index].interpolated(to: polyline[index + 1], t: -first / span)
            if !chooseLast { break }
        }
        return found.map { $0 + axis * (depth - projection($0)) }
    }
}
