// Copyright 2026 the img2bez Authors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Ported to Swift and materially modified for beztrace.

import Foundation

struct SubpixelContour: Equatable, Sendable {
    let points: [Point2D]

    var signedArea: Double { polygonSignedArea(of: points) }
    var winding: Winding { polygonWinding(of: points) }
    var bounds: Bounds? { Bounds(points: points) }
    var isFinite: Bool { points.allSatisfy(\.isFinite) }
}

enum CellEdge: Equatable, Sendable {
    case top
    case bottom
    case left
    case right
}

struct CellSegment: Equatable, Sendable {
    let first: CellEdge
    let second: CellEdge

    init(_ first: CellEdge, _ second: CellEdge) {
        self.first = first
        self.second = second
    }
}

private struct EdgeKey: Equatable, Hashable, Comparable, Sendable {
    let x: Int
    let y: Int
    let horizontal: Bool

    static func < (lhs: EdgeKey, rhs: EdgeKey) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return !lhs.horizontal && rhs.horizontal
    }
}

enum SubpixelExtractor {
    private static let frameContourThreshold = 0.9
    private static let frameHugFraction = 0.5
    private static let frameBorderPixels = 2.5

    static func segments(for code: UInt8, centerInside: Bool) -> [CellSegment] {
        switch code {
        case 0, 15:
            return []
        case 1, 14:
            return [CellSegment(.top, .left)]
        case 2, 13:
            return [CellSegment(.top, .right)]
        case 3, 12:
            return [CellSegment(.left, .right)]
        case 4, 11:
            return [CellSegment(.left, .bottom)]
        case 8, 7:
            return [CellSegment(.right, .bottom)]
        case 5, 10:
            return [CellSegment(.top, .bottom)]
        case 6, 9:
            let isolateTopLeftAndBottomRight = (code == 6) == centerInside
            if isolateTopLeftAndBottomRight {
                return [CellSegment(.top, .left), CellSegment(.right, .bottom)]
            }
            return [CellSegment(.top, .right), CellSegment(.left, .bottom)]
        default:
            preconditionFailure("marching-squares code must fit in four bits")
        }
    }

    static func extract(
        raster: GrayRaster,
        threshold: UInt8,
        invert: Bool,
        minimumAreaPixels: Double
    ) -> [SubpixelContour] {
        let iso = Double(threshold) + 0.5
        let width = raster.width
        let height = raster.height
        let field: (Int, Int) -> Double = { x, y in
            guard x >= 0, x < width, y >= 0, y < height else {
                return invert ? -iso : iso - 255
            }
            let luma = Double(raster.pixels[y * width + x])
            return invert ? luma - iso : iso - luma
        }
        return extractField(
            width: width,
            height: height,
            field: field,
            minimumAreaPixels: minimumAreaPixels
        )
    }

    static func glyphContours(
        raster: GrayRaster,
        threshold: UInt8,
        invert: Bool,
        minimumAreaPixels: Double
    ) -> [SubpixelContour] {
        extract(
            raster: raster,
            threshold: threshold,
            invert: invert,
            minimumAreaPixels: minimumAreaPixels
        ).filter { contour in
            guard let bounds = contour.bounds else { return false }
            let frameSized = bounds.width > Double(raster.width) * frameContourThreshold
                && bounds.height > Double(raster.height) * frameContourThreshold
            guard frameSized else { return true }
            let nearBorder = contour.points.reduce(into: 0) { count, point in
                if point.x <= frameBorderPixels
                    || point.y <= frameBorderPixels
                    || point.x >= Double(raster.width) - frameBorderPixels
                    || point.y >= Double(raster.height) - frameBorderPixels
                {
                    count += 1
                }
            }
            return Double(nearBorder) < Double(contour.points.count) * frameHugFraction
        }
    }

    private static func extractField(
        width: Int,
        height: Int,
        field: (Int, Int) -> Double,
        minimumAreaPixels: Double
    ) -> [SubpixelContour] {
        func edgeKey(cellX: Int, cellY: Int, edge: CellEdge) -> EdgeKey {
            switch edge {
            case .top:
                return EdgeKey(x: cellX + 1, y: cellY + 1, horizontal: true)
            case .bottom:
                return EdgeKey(x: cellX + 1, y: cellY + 2, horizontal: true)
            case .left:
                return EdgeKey(x: cellX + 1, y: cellY + 1, horizontal: false)
            case .right:
                return EdgeKey(x: cellX + 2, y: cellY + 1, horizontal: false)
            }
        }

        var links: [EdgeKey: [EdgeKey]] = [:]
        func addSegment(_ first: EdgeKey, _ second: EdgeKey) {
            links[first, default: []].append(second)
            links[second, default: []].append(first)
        }

        for cellY in -1..<height {
            for cellX in -1..<width {
                let topLeft = field(cellX, cellY)
                let topRight = field(cellX + 1, cellY)
                let bottomLeft = field(cellX, cellY + 1)
                let bottomRight = field(cellX + 1, cellY + 1)
                let code = UInt8(topLeft > 0 ? 1 : 0)
                    | UInt8(topRight > 0 ? 2 : 0)
                    | UInt8(bottomLeft > 0 ? 4 : 0)
                    | UInt8(bottomRight > 0 ? 8 : 0)
                if code == 0 || code == 15 { continue }
                let centerInside = (topLeft + topRight + bottomLeft + bottomRight) * 0.25 > 0
                for segment in segments(for: code, centerInside: centerInside) {
                    addSegment(
                        edgeKey(cellX: cellX, cellY: cellY, edge: segment.first),
                        edgeKey(cellX: cellX, cellY: cellY, edge: segment.second)
                    )
                }
            }
        }

        func crossing(_ key: EdgeKey) -> Point2D {
            let ax = key.x - 1
            let ay = key.y - 1
            let bx = key.horizontal ? ax + 1 : ax
            let by = key.horizontal ? ay : ay + 1
            let first = field(ax, ay)
            let second = field(bx, by)
            let fraction: Double
            if abs(first - second) < 1e-12 {
                fraction = 0.5
            } else {
                fraction = min(max(first / (first - second), 0.001), 0.999)
            }
            let x = Double(ax) + 0.5 + fraction * Double(bx - ax)
            let yDown = Double(ay) + 0.5 + fraction * Double(by - ay)
            return Point2D(x: x, y: Double(height) - yDown)
        }

        var visited: Set<EdgeKey> = []
        var contours: [SubpixelContour] = []
        for start in links.keys.sorted() {
            if visited.contains(start) { continue }
            guard let neighbors = links[start], neighbors.count == 2 else {
                visited.insert(start)
                continue
            }
            var loopKeys = [start]
            visited.insert(start)
            var previous = start
            var current = neighbors[0]
            while current != start {
                visited.insert(current)
                loopKeys.append(current)
                guard let nextLinks = links[current], nextLinks.count == 2 else { break }
                let next = nextLinks[0] == previous ? nextLinks[1] : nextLinks[0]
                previous = current
                current = next
            }
            guard loopKeys.count >= 8 else { continue }
            let contour = SubpixelContour(points: loopKeys.map(crossing))
            if abs(contour.signedArea) >= minimumAreaPixels {
                contours.append(contour)
            }
        }
        return contours
    }
}
