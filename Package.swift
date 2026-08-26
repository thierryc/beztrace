// swift-tools-version: 6.0
// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import PackageDescription

let package = Package(
    name: "beztrace",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "BezierTraceCore", targets: ["BezierTraceCore"]),
        .executable(name: "beztrace", targets: ["BezierTraceCommand"]),
        // Maintenance-only sanitizer driver; never included in release staging.
        .executable(name: "beztrace-fuzz-harness", targets: ["BezierTraceFuzzHarness"]),
    ],
    targets: [
        .target(name: "BezierTraceCore"),
        .executableTarget(
            name: "BezierTraceCommand",
            dependencies: ["BezierTraceCore"]
        ),
        .executableTarget(
            name: "BezierTraceFuzzHarness",
            dependencies: ["BezierTraceCore"],
            path: "Tests/FuzzHarness"
        ),
        .testTarget(
            name: "BezierTraceCoreTests",
            dependencies: ["BezierTraceCore"]
        ),
        .testTarget(
            name: "BezierTraceCommandTests",
            dependencies: ["BezierTraceCommand", "BezierTraceCore"]
        ),
    ]
)
