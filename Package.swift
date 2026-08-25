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
    ],
    targets: [
        .target(name: "BezierTraceCore"),
        .executableTarget(
            name: "BezierTraceCommand",
            dependencies: ["BezierTraceCore"]
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
