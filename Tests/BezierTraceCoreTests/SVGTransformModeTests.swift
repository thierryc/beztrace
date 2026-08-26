// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CoreGraphics
import Foundation
import XCTest
import BezierTraceCore

final class SVGTransformModeTests: XCTestCase {
    func testPreserveMatchesLegacyBytesAndBakeReflectsEveryPathPoint() throws {
        let result = try trace("corpus/deterministic/glyphs/glyph-upper-o.png")
        let bounds = try XCTUnwrap(result.bounds)
        let flip = bounds.minY + bounds.maxY
        let rawPath = TraceSerializer.svgPathData(for: result.outline)
        let expectedLegacy = "<svg xmlns=\"http://www.w3.org/2000/svg\" "
            + "viewBox=\"\(number(bounds.minX)) \(number(bounds.minY)) "
            + "\(number(bounds.width)) \(number(bounds.height))\">"
            + "<g transform=\"translate(0 \(number(flip))) scale(1 -1)\">"
            + "<path d=\"\(rawPath)\" fill=\"black\" fill-rule=\"nonzero\"/>"
            + "</g></svg>\n"

        let defaultSVG = try TraceSerializer.svg(result)
        let bakedSVG = try TraceSerializer.svg(result, transformMode: .bake)
        let preservedSVG = try TraceSerializer.svg(result, transformMode: .preserve)
        XCTAssertEqual(defaultSVG, bakedSVG)
        XCTAssertEqual(preservedSVG, expectedLegacy)
        XCTAssertFalse(bakedSVG.contains("<g"))
        XCTAssertFalse(bakedSVG.contains("transform="))

        let baked = try ParsedSVG(bakedSVG)
        let preserved = try ParsedSVG(preservedSVG)
        XCTAssertEqual(baked.viewBox, preserved.viewBox)
        XCTAssertFalse(baked.hasTransform)
        XCTAssertTrue(preserved.hasTransform)
        assertSameTopology(baked.commands, preserved.commands)
        assertCommandsEqual(
            baked.commands,
            screenSpaceCommands(from: preserved),
            accuracy: 1e-9
        )

        let preservedAreas = contourAreas(preserved.commands)
        let bakedAreas = contourAreas(baked.commands)
        XCTAssertEqual(preservedAreas.count, 2)
        XCTAssertEqual(bakedAreas.count, preservedAreas.count)
        XCTAssertTrue(preservedAreas.contains(where: { $0 > 0 }))
        XCTAssertTrue(preservedAreas.contains(where: { $0 < 0 }))
        for (before, after) in zip(preservedAreas, bakedAreas) {
            XCTAssertEqual(before.sign, -after.sign)
        }

        let preservedCoverage = try rasterize(
            screenSpaceCommands(from: preserved),
            in: preserved.viewBox
        )
        let bakedCoverage = try rasterize(baked.commands, in: baked.viewBox)
        XCTAssertEqual(bakedCoverage, preservedCoverage)
    }

    func testBakeUsesTheResolvedPlacedViewBoxAxis() throws {
        let result = try BezierTracer.trace(TraceRequest(
            imageData: try fixtureData("corpus/deterministic/glyphs/glyph-upper-a.png"),
            placement: PlacementOptions(
                targetYMin: -200,
                targetYMax: 700,
                horizontalMode: .centered(advance: 900)
            )
        ))
        let baked = try ParsedSVG(TraceSerializer.svg(result, transformMode: .bake))
        let preserved = try ParsedSVG(TraceSerializer.svg(result, transformMode: .preserve))

        XCTAssertEqual(baked.viewBox.minX, 0)
        XCTAssertEqual(baked.viewBox.minY, -200)
        XCTAssertEqual(baked.viewBox.maxX, 900)
        XCTAssertEqual(baked.viewBox.maxY, 700)
        assertCommandsEqual(
            baked.commands,
            screenSpaceCommands(from: preserved),
            accuracy: 1e-9
        )
        let reflectionAxisSum = baked.viewBox.minY + baked.viewBox.maxY
        for (source, destination) in zip(points(in: preserved.commands), points(in: baked.commands)) {
            XCTAssertEqual(source.x, destination.x, accuracy: 1e-9)
            XCTAssertEqual(destination.y, reflectionAxisSum - source.y, accuracy: 1e-9)
        }
    }

    func testFocusedMultipleCounterGlyphHasIdenticalCoverageInBothModes() throws {
        let result = try trace("corpus/deterministic/glyphs/glyph-8.png")
        let baked = try ParsedSVG(TraceSerializer.svg(result, transformMode: .bake))
        let preserved = try ParsedSVG(TraceSerializer.svg(result, transformMode: .preserve))

        XCTAssertGreaterThanOrEqual(contourAreas(baked.commands).count, 3)
        assertCommandsEqual(
            baked.commands,
            screenSpaceCommands(from: preserved),
            accuracy: 1e-9
        )
        XCTAssertEqual(
            try rasterize(baked.commands, in: baked.viewBox),
            try rasterize(screenSpaceCommands(from: preserved), in: preserved.viewBox)
        )
    }

    private func trace(_ path: String) throws -> TraceResult {
        try BezierTracer.trace(TraceRequest(imageData: try fixtureData(path)))
    }

    private func fixtureData(_ path: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(path))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct SVGPoint: Equatable {
    let x: Double
    let y: Double
}

private enum SVGCommand: Equatable {
    case move(SVGPoint)
    case line(SVGPoint)
    case cubic(SVGPoint, SVGPoint, SVGPoint)
    case close

    func mapPoints(_ transform: (SVGPoint) -> SVGPoint) -> SVGCommand {
        switch self {
        case .move(let point): return .move(transform(point))
        case .line(let point): return .line(transform(point))
        case .cubic(let first, let second, let end):
            return .cubic(transform(first), transform(second), transform(end))
        case .close: return .close
        }
    }
}

private struct ParsedSVG {
    let viewBox: Rect
    let commands: [SVGCommand]
    let hasTransform: Bool

    init(_ svg: String) throws {
        let viewBoxValues = try attribute("viewBox", in: svg).split(separator: " ").map {
            guard let value = Double($0) else { throw SVGTestError.malformedNumber(String($0)) }
            return value
        }
        guard viewBoxValues.count == 4 else { throw SVGTestError.malformedViewBox }
        viewBox = Rect(
            minX: viewBoxValues[0],
            minY: viewBoxValues[1],
            maxX: viewBoxValues[0] + viewBoxValues[2],
            maxY: viewBoxValues[1] + viewBoxValues[3]
        )
        commands = try parsePath(try attribute("d", in: svg))
        hasTransform = svg.contains("<g transform=")
    }
}

private enum SVGTestError: Error {
    case missingAttribute(String)
    case malformedViewBox
    case malformedCommand(String)
    case malformedNumber(String)
    case rasterContext
}

private func attribute(_ name: String, in svg: String) throws -> String {
    let prefix = "\(name)=\""
    guard let start = svg.range(of: prefix)?.upperBound,
          let end = svg[start...].firstIndex(of: "\"")
    else { throw SVGTestError.missingAttribute(name) }
    return String(svg[start..<end])
}

private func parsePath(_ path: String) throws -> [SVGCommand] {
    let tokens = path.split(separator: " ").map(String.init)
    var result: [SVGCommand] = []
    var index = 0
    func coordinate(_ token: String) throws -> Double {
        guard let value = Double(token) else { throw SVGTestError.malformedNumber(token) }
        return value
    }
    func firstCoordinate(_ token: String) throws -> Double {
        try coordinate(String(token.dropFirst()))
    }
    while index < tokens.count {
        let token = tokens[index]
        guard let command = token.first else { throw SVGTestError.malformedCommand(token) }
        switch command {
        case "M":
            guard index + 1 < tokens.count else { throw SVGTestError.malformedCommand(token) }
            result.append(.move(SVGPoint(
                x: try firstCoordinate(token),
                y: try coordinate(tokens[index + 1])
            )))
            index += 2
        case "L":
            guard index + 1 < tokens.count else { throw SVGTestError.malformedCommand(token) }
            result.append(.line(SVGPoint(
                x: try firstCoordinate(token),
                y: try coordinate(tokens[index + 1])
            )))
            index += 2
        case "C":
            guard index + 5 < tokens.count else { throw SVGTestError.malformedCommand(token) }
            result.append(.cubic(
                SVGPoint(x: try firstCoordinate(token), y: try coordinate(tokens[index + 1])),
                SVGPoint(x: try coordinate(tokens[index + 2]), y: try coordinate(tokens[index + 3])),
                SVGPoint(x: try coordinate(tokens[index + 4]), y: try coordinate(tokens[index + 5]))
            ))
            index += 6
        case "Z":
            guard token == "Z" else { throw SVGTestError.malformedCommand(token) }
            result.append(.close)
            index += 1
        default:
            throw SVGTestError.malformedCommand(token)
        }
    }
    return result
}

private func screenSpaceCommands(from svg: ParsedSVG) -> [SVGCommand] {
    guard svg.hasTransform else { return svg.commands }
    let flip = svg.viewBox.minY + svg.viewBox.maxY
    return svg.commands.map { command in
        command.mapPoints { SVGPoint(x: $0.x, y: flip - $0.y) }
    }
}

private func points(in commands: [SVGCommand]) -> [SVGPoint] {
    commands.flatMap { command -> [SVGPoint] in
        switch command {
        case .move(let point), .line(let point): return [point]
        case .cubic(let first, let second, let end): return [first, second, end]
        case .close: return []
        }
    }
}

private func assertSameTopology(
    _ first: [SVGCommand],
    _ second: [SVGCommand],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(first.count, second.count, file: file, line: line)
    for (lhs, rhs) in zip(first, second) {
        let same: Bool
        switch (lhs, rhs) {
        case (.move, .move), (.line, .line), (.cubic, .cubic), (.close, .close): same = true
        default: same = false
        }
        XCTAssertTrue(same, "SVG segment topology differs", file: file, line: line)
    }
}

private func assertCommandsEqual(
    _ first: [SVGCommand],
    _ second: [SVGCommand],
    accuracy: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertSameTopology(first, second, file: file, line: line)
    let lhs = points(in: first)
    let rhs = points(in: second)
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (left, right) in zip(lhs, rhs) {
        XCTAssertEqual(left.x, right.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.y, right.y, accuracy: accuracy, file: file, line: line)
    }
}

private func contourAreas(_ commands: [SVGCommand]) -> [Double] {
    var result: [Double] = []
    var points: [SVGPoint] = []
    var current: SVGPoint?

    func finish() {
        guard points.count >= 3 else {
            points.removeAll(keepingCapacity: true)
            current = nil
            return
        }
        var area = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        result.append(area / 2)
        points.removeAll(keepingCapacity: true)
        current = nil
    }

    for command in commands {
        switch command {
        case .move(let point):
            if !points.isEmpty { finish() }
            points.append(point)
            current = point
        case .line(let point):
            points.append(point)
            current = point
        case .cubic(let control1, let control2, let end):
            guard let start = current else { continue }
            for step in 1...24 {
                let t = Double(step) / 24
                let inverse = 1 - t
                points.append(SVGPoint(
                    x: inverse * inverse * inverse * start.x
                        + 3 * inverse * inverse * t * control1.x
                        + 3 * inverse * t * t * control2.x
                        + t * t * t * end.x,
                    y: inverse * inverse * inverse * start.y
                        + 3 * inverse * inverse * t * control1.y
                        + 3 * inverse * t * t * control2.y
                        + t * t * t * end.y
                ))
            }
            current = end
        case .close:
            finish()
        }
    }
    if !points.isEmpty { finish() }
    return result
}

private func rasterize(_ commands: [SVGCommand], in viewBox: Rect, size: Int = 192) throws -> [UInt8] {
    let byteCount = size * size
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
    defer { buffer.deallocate() }
    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    guard let context = CGContext(
        data: buffer,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { throw SVGTestError.rasterContext }
    let path = CGMutablePath()
    func point(_ value: SVGPoint) -> CGPoint {
        CGPoint(
            x: (value.x - viewBox.minX) * Double(size) / viewBox.width,
            y: (value.y - viewBox.minY) * Double(size) / viewBox.height
        )
    }
    for command in commands {
        switch command {
        case .move(let value): path.move(to: point(value))
        case .line(let value): path.addLine(to: point(value))
        case .cubic(let first, let second, let end):
            path.addCurve(to: point(end), control1: point(first), control2: point(second))
        case .close: path.closeSubpath()
        }
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(path)
    context.fillPath(using: .winding)
    return Array(UnsafeBufferPointer(
        start: buffer.assumingMemoryBound(to: UInt8.self),
        count: byteCount
    ))
}

private func number(_ value: Double) -> String {
    if value == 0 { return "0" }
    let rounded = value.rounded()
    if abs(value - rounded) <= 1e-9,
       rounded >= Double(Int64.min), rounded <= Double(Int64.max)
    {
        return String(Int64(rounded))
    }
    return String(value)
}

private extension Double {
    var sign: Double { self < 0 ? -1 : 1 }
}
