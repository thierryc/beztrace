// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

public enum SVGTransformMode: String, Codable, Equatable, Sendable {
    case bake
    case preserve
}

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

    public static func svg(
        _ result: TraceResult,
        transformMode: SVGTransformMode = .bake
    ) throws -> String {
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
        let flip = viewBounds.minY + viewBounds.maxY
        let opening = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(number(viewBounds.minX)) \(number(viewBounds.minY)) \(number(viewBounds.width)) \(number(viewBounds.height))\">"
        switch transformMode {
        case .bake:
            let path = svgPathData(for: result.outline) { flip - $0 }
            return "\(opening)<path d=\"\(path)\" fill=\"black\" fill-rule=\"nonzero\"/></svg>\n"
        case .preserve:
            let path = svgPathData(for: result.outline)
            return "\(opening)<g transform=\"translate(0 \(number(flip))) scale(1 -1)\"><path d=\"\(path)\" fill=\"black\" fill-rule=\"nonzero\"/></g></svg>\n"
        }
    }

    public static func svgPathData(for outline: Outline) -> String {
        svgPathData(for: outline) { $0 }
    }

    private static func svgPathData(
        for outline: Outline,
        transformY: (Double) -> Double
    ) -> String {
        outline.contours.compactMap { contour -> String? in
            guard let first = contour.nodes.first(where: { $0.type != .offcurve }) else { return nil }
            var commands = ["M\(number(first.x)) \(number(transformY(first.y)))"]
            for segment in contour.segments() {
                if segment.cubic.end.distance(to: first.point) < 1e-9, segment.isLine {
                    continue
                }
                if segment.isLine {
                    commands.append(
                        "L\(number(segment.cubic.end.x)) \(number(transformY(segment.cubic.end.y)))"
                    )
                } else {
                    commands.append(
                        "C\(number(segment.cubic.control1.x)) \(number(transformY(segment.cubic.control1.y))) "
                            + "\(number(segment.cubic.control2.x)) \(number(transformY(segment.cubic.control2.y))) "
                            + "\(number(segment.cubic.end.x)) \(number(transformY(segment.cubic.end.y)))"
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
