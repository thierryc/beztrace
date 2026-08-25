// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

public enum TraceSerializer {
    public static func json(_ result: TraceResult, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .throw
        do {
            return try encoder.encode(result)
        } catch {
            throw TraceError.serialization(String(describing: error))
        }
    }

    public static func svg(_ result: TraceResult) throws -> String {
        guard let geometricBounds = result.bounds else {
            throw TraceError.serialization("outline has no bounds")
        }
        let viewBounds: Rect
        if let placement = result.placement {
            viewBounds = Rect(
                minX: 0,
                minY: placement.targetYMin,
                maxX: placement.advanceWidth,
                maxY: placement.targetYMax
            )
        } else {
            viewBounds = geometricBounds
        }
        guard viewBounds.isFiniteAndOrdered else {
            throw TraceError.serialization("SVG view box is invalid")
        }
        let path = svgPathData(for: result.outline)
        let flip = viewBounds.minY + viewBounds.maxY
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(number(viewBounds.minX)) \(number(viewBounds.minY)) \(number(viewBounds.width)) \(number(viewBounds.height))\"><g transform=\"translate(0 \(number(flip))) scale(1 -1)\"><path d=\"\(path)\" fill=\"black\" fill-rule=\"nonzero\"/></g></svg>\n"
    }

    public static func svgPathData(for outline: Outline) -> String {
        outline.contours.compactMap { contour -> String? in
            guard let first = contour.nodes.first(where: { $0.type != .offcurve }) else { return nil }
            var commands = ["M\(number(first.x)) \(number(first.y))"]
            for segment in contour.segments() {
                if segment.cubic.end.distance(to: first.point) < 1e-9, segment.isLine {
                    continue
                }
                if segment.isLine {
                    commands.append("L\(number(segment.cubic.end.x)) \(number(segment.cubic.end.y))")
                } else {
                    commands.append(
                        "C\(number(segment.cubic.control1.x)) \(number(segment.cubic.control1.y)) "
                            + "\(number(segment.cubic.control2.x)) \(number(segment.cubic.control2.y)) "
                            + "\(number(segment.cubic.end.x)) \(number(segment.cubic.end.y))"
                    )
                }
            }
            commands.append("Z")
            return commands.joined(separator: " ")
        }.joined(separator: " ")
    }

    private static func number(_ value: Double) -> String {
        if value == 0 { return "0" }
        let rounded = value.rounded()
        if abs(value - rounded) <= 1e-9,
           rounded >= Double(Int64.min), rounded <= Double(Int64.max)
        {
            return String(Int64(rounded))
        }
        return String(value)
    }
}
