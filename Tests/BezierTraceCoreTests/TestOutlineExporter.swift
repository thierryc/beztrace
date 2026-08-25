// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
@testable import BezierTraceCore

enum TestOutlineExporter {
    static func writeUFO(_ outlines: [(name: String, outline: ValidatedOutline)], to root: URL) throws {
        let fileManager = FileManager.default
        let glyphs = root.appendingPathComponent("glyphs", isDirectory: true)
        try fileManager.createDirectory(at: glyphs, withIntermediateDirectories: true)
        let contents = Dictionary(uniqueKeysWithValues: outlines.enumerated().map {
            ($0.element.name, String(format: "glyph%03d.glif", $0.offset))
        })
        try writePlist(["creator": "org.beztrace.tests", "formatVersion": 3], to: root.appendingPathComponent("metainfo.plist"))
        try writePlist([["public.default", "glyphs"]], to: root.appendingPathComponent("layercontents.plist"))
        try writePlist(contents, to: glyphs.appendingPathComponent("contents.plist"))
        try writePlist(["color": "0,0,0,1", "lib": [:]], to: glyphs.appendingPathComponent("layerinfo.plist"))
        for record in outlines {
            let xml = glif(name: record.name, outline: record.outline)
            try Data(xml.utf8).write(to: glyphs.appendingPathComponent(contents[record.name]!))
        }
    }

    private static func writePlist(_ value: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private static func glif(name: String, outline: ValidatedOutline) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<glyph name=\"\(name)\" format=\"2\">",
            "  <advance width=\"1088\"/>",
            "  <outline>",
        ]
        for contour in outline.contours {
            lines.append("    <contour>")
            for point in contour.points {
                var attributes = "x=\"\(number(point.position.x))\" y=\"\(number(point.position.y))\""
                if let kind = point.kind.oracleName { attributes += " type=\"\(kind)\"" }
                if point.smooth { attributes += " smooth=\"yes\"" }
                lines.append("      <point \(attributes)/>")
            }
            lines.append("    </contour>")
        }
        lines.append("  </outline>")
        lines.append("</glyph>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 1e-9 { return String(Int64(rounded)) }
        var result = String(format: "%.12f", value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}
