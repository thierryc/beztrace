# Swift port map

This inventory maps the Milestone 2 Swift foundations to the sole authorized
img2bez baseline, commit
`23073ca08ecdac61ad0e838bfae49a590bc2c7cc`. It distinguishes translated
img2bez behavior from independently written Apple-platform adapters and local
geometry so that later work can preserve attribution without importing Rust
dependency implementations.

| Swift file | Baseline source or behavior | Material Swift changes |
| --- | --- | --- |
| `Geometry.swift` | Geometry concepts used by `src/model/geom.rs` and the tracing pipeline | Independently written local `Double` primitives replace `kurbo`; deterministic comparison, affine inversion, exact cubic bounds, and winding helpers are local. |
| `Raster.swift` | `src/io/bitmap.rs` and `src/pipeline/preprocess.rs` | ImageIO/CoreGraphics replace Rust image dependencies. The adapter accepts PNG/JPEG only, normalizes EXIF orientation and alpha, enforces byte/dimension limits, and implements deterministic Otsu and bounded low-resolution recovery. Photo-profile preprocessing is excluded. |
| `SubpixelContours.swift` | `src/pipeline/vectorize/subpixel.rs`; image-frame filtering behavior from `src/pipeline/vectorize/mod.rs` | Marching-squares cases, saddle resolution, interpolation, closure, minimum contour filtering, and deterministic edge ordering are ported. Swift collection and numeric representations replace Rust types. |
| `ContourPipeline.swift` | Front-half orchestration across preprocessing and vectorization | Adds a bounded `Data`-to-contours composition point for internal tests and fails closed on invalid options, missing contours, or non-finite coordinates. It is not a public tracing API. |
| `CoreError.swift` | No direct translated file | Original beztrace error domain for Apple decoder, resource-bound, raster, and contour failures. |
| `BezierTraceCore.swift` | No direct translated file | Original milestone-status placeholder. Public request/result contracts remain deferred. |

Every translated source file retains the img2bez copyright and
`SPDX-License-Identifier: Apache-2.0 OR MIT` notice plus a Swift port/material
changes statement. Apple system frameworks are platform dependencies, not
bundled third-party code. No Rust dependency source was translated in this
milestone.

The corresponding differential evidence is immutable under
`Tests/Fixtures/oracle/v1`. The Swift tests compare every Basic Latin subpixel
contour against those captures and require topology agreement for all 24
reviewed input images.
