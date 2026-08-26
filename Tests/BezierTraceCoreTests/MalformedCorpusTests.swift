// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation
import XCTest
@testable import BezierTraceCore

final class MalformedCorpusTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Entry: Decodable { let path: String; let size: Int; let sha256: String }
        let count: Int
        let files: [Entry]
    }

    func testAllCommittedMutationsFailClosedOrReturnValidFiniteGeometry() throws {
        let root = repositoryRoot.appendingPathComponent("Tests/Fixtures/malformed/v1", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(manifest.count, 256)
        XCTAssertEqual(manifest.files.count, 256)
        for entry in manifest.files {
            let data = try Data(contentsOf: root.appendingPathComponent(entry.path))
            XCTAssertEqual(data.count, entry.size, entry.path)
            do {
                let result = try BezierTracer.trace(TraceRequest(imageData: data))
                XCTAssertTrue(result.outline.contours.allSatisfy(\.closed), entry.path)
                XCTAssertTrue(
                    result.outline.contours.flatMap(\.nodes).allSatisfy { $0.x.isFinite && $0.y.isFinite },
                    entry.path
                )
            } catch let error as TraceError {
                XCTAssertFalse(String(describing: error).isEmpty, entry.path)
            } catch {
                XCTFail("unexpected error domain for \(entry.path): \(error)")
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
