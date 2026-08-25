// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

extension Rect {
    var isFiniteAndOrdered: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
            && maxX > minX && maxY > minY
    }

    init(_ bounds: Bounds) {
        self.init(minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY)
    }
}

extension Node {
    var point: Point2D { Point2D(x: x, y: y) }
}

struct OutlineSegment {
    let cubic: CubicBezier
    let isLine: Bool
}

extension Contour {
    func segments() -> [OutlineSegment] {
        guard nodes.count >= 2,
              let startIndex = nodes.firstIndex(where: { $0.type != .offcurve })
        else { return [] }
        var result: [OutlineSegment] = []
        var current = nodes[startIndex].point
        var cursor = (startIndex + 1) % nodes.count
        var consumed = 0
        while consumed < nodes.count {
            let node = nodes[cursor]
            if node.type == .offcurve {
                let secondIndex = (cursor + 1) % nodes.count
                let endIndex = (cursor + 2) % nodes.count
                let second = nodes[secondIndex]
                let end = nodes[endIndex]
                guard second.type == .offcurve, end.type == .curve else { return [] }
                result.append(OutlineSegment(
                    cubic: CubicBezier(
                        start: current,
                        control1: node.point,
                        control2: second.point,
                        end: end.point
                    ),
                    isLine: false
                ))
                current = end.point
                cursor = (endIndex + 1) % nodes.count
                consumed += 3
            } else {
                result.append(OutlineSegment(
                    cubic: CubicBezier(
                        start: current,
                        control1: current,
                        control2: node.point,
                        end: node.point
                    ),
                    isLine: true
                ))
                current = node.point
                cursor = (cursor + 1) % nodes.count
                consumed += 1
            }
        }
        return result
    }

    mutating func normalizeStart(rtl: Bool) {
        var best: (index: Int, y: Double, x: Double)?
        for index in nodes.indices where nodes[index].type != .offcurve {
            let node = nodes[index]
            let better = best == nil
                || node.y < best!.y - 1e-9
                || (node.y < best!.y + 1e-9
                    && (rtl ? node.x > best!.x + 1e-9 : node.x < best!.x - 1e-9))
            if better { best = (index, node.y, node.x) }
        }
        if let best, best.index > 0 {
            nodes = Array(nodes[best.index...]) + Array(nodes[..<best.index])
        }
    }
}

extension Outline {
    var tightBounds: Rect? {
        var result: Bounds?
        for segment in contours.flatMap({ $0.segments() }) {
            let bounds = segment.cubic.bounds
            result = result.map { $0.union(bounds) } ?? bounds
        }
        return result.map(Rect.init)
    }

    var onCurveBounds: Rect? {
        let points = contours.flatMap(\.nodes).filter { $0.type != .offcurve }.map(\.point)
        return Bounds(points: points).map(Rect.init)
    }

    func transformed(scale: Double = 1, dx: Double = 0, dy: Double = 0) -> Outline {
        Outline(contours: contours.map { contour in
            Contour(closed: contour.closed, nodes: contour.nodes.map { node in
                Node(
                    x: node.x * scale + dx,
                    y: node.y * scale + dy,
                    type: node.type,
                    smooth: node.smooth
                )
            })
        })
    }

    mutating func normalizeStarts(rtl: Bool) {
        for index in contours.indices { contours[index].normalizeStart(rtl: rtl) }
    }
}
