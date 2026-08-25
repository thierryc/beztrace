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
    ],
    targets: [
        .target(name: "BezierTraceCore"),
        .testTarget(
            name: "BezierTraceCoreTests",
            dependencies: ["BezierTraceCore"]
        ),
    ]
)
