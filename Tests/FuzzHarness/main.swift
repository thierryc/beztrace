// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import BezierTraceCore
import Foundation

@main
enum FuzzHarness {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let countText = environment["BEZTRACE_FUZZ_CASES"],
              let count = Int(countText), count > 0,
              let seedPath = environment["BEZTRACE_FUZZ_SEED"],
              let reportPath = environment["BEZTRACE_FUZZ_REPORT"]
        else {
            FileHandle.standardError.write(Data(
                "set BEZTRACE_FUZZ_CASES, BEZTRACE_FUZZ_SEED, and BEZTRACE_FUZZ_REPORT\n".utf8
            ))
            Foundation.exit(2)
        }
        guard FileManager.default.fileExists(atPath: seedPath) else {
            throw HarnessError.missingSeed
        }
        var random = SplitMix64(seed: 0xB37A_CE50_2026_F022)
        var accepted = 0
        var rejected = 0
        let started = Date()
        for index in 0..<count {
            let length = 4 + Int(random.next() % 8_188)
            var bytes = [UInt8](repeating: 0, count: length)
            for offset in bytes.indices { bytes[offset] = UInt8(truncatingIfNeeded: random.next()) }
            // Force a private non-image signature. The committed 256-case
            // smoke corpus covers structured PNG mutations; this larger ASan
            // campaign stresses bounded arbitrary byte storage without asking
            // an uninstrumented system decoder to fuzz third-party codecs.
            bytes.replaceSubrange(0..<4, with: [66, 90, 70, 90]) // BZFZ
            let data = Data(bytes)
            do {
                let result = try BezierTracer.trace(TraceRequest(imageData: data))
                guard result.outline.contours.allSatisfy({ $0.closed }),
                      result.outline.contours.flatMap(\.nodes).allSatisfy({
                          $0.x.isFinite && $0.y.isFinite
                      })
                else { throw HarnessError.invalidSuccessfulResult(index) }
                accepted += 1
            } catch is TraceError {
                rejected += 1
            }
        }
        let sanitizer = environment["ASAN_OPTIONS"] == nil ? "none" : "address"
        let report: [String: Any] = [
            "schemaVersion": 1,
            "seed": "0xB37ACE502026F022",
            "cases": count,
            "accepted": accepted,
            "rejected": rejected,
            "durationSeconds": Date().timeIntervalSince(started),
            "sanitizer": sanitizer,
        ]
        let output = URL(fileURLWithPath: reportPath)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: output)
        print("\(sanitizer) fuzz campaign: \(count) cases, \(accepted) accepted, \(rejected) rejected")
    }
}

private enum HarnessError: Error { case invalidSuccessfulResult(Int); case missingSeed }

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
