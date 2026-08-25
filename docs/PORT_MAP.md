# Swift port map

This inventory maps the Milestone 2 and 3 Swift implementation to the sole
authorized img2bez baseline, commit
`23073ca08ecdac61ad0e838bfae49a590bc2c7cc`. It distinguishes translated
img2bez behavior from independently written Apple-platform adapters and local
geometry so that later work can preserve attribution without importing Rust
dependency implementations.

| Swift file | Baseline source or behavior | Material Swift changes |
| --- | --- | --- |
| `Geometry.swift` | Geometry concepts used by `src/model/geom.rs` and the tracing pipeline | Independently written local `Double` primitives replace `kurbo`; deterministic comparison, affine inversion, exact cubic bounds, and winding helpers are local. |
| `Raster.swift` | `src/io/bitmap.rs` and `src/pipeline/preprocess.rs` | ImageIO/CoreGraphics replace Rust image dependencies. The adapter accepts PNG/JPEG only, normalizes EXIF orientation and alpha, enforces byte/dimension limits, and implements deterministic Otsu and bounded low-resolution recovery. Photo-profile preprocessing is excluded. |
| `SubpixelContours.swift` | `src/pipeline/vectorize/subpixel.rs`; image-frame filtering behavior from `src/pipeline/vectorize/mod.rs` | Marching-squares cases, saddle resolution, interpolation, closure, minimum contour filtering, and deterministic edge ordering are ported. Swift collection and numeric representations replace Rust types. |
| `CornerDetection.swift`, `StraightRuns.swift`, `StructuralPlanning.swift` | `src/pipeline/vectorize/fit/plan.rs` and its planning helpers | Port closed resampling, adaptive smoothing, curvature, corner/run/extremum/inflection evidence, split normalization, and line-section planning. Swift preserves pinned signed-zero and cyclic-order behavior explicitly. |
| `RasterTarget.swift` | Raster target and distance/loss behavior used by pinned fitting/refinement modules | Implements a bounded Swift raster view and deterministic coverage/distance sampling without translating an image dependency. |
| `FittedGeometry.swift`, `CubicFitting.swift`, `FittingFinish.swift` | Pinned vector fitting, curve fitting, subdivision, and finishing modules | Replace Rust/`kurbo` value types and solvers with local `Double` geometry while preserving constrained tangents, the 24-segment fallback bound, line provenance, join harmonization, and handle caps. |
| `RasterRefinement.swift`, `RefinementFlats.swift`, `RefinementLines.swift`, `RefinementMerge.swift`, `RefinementPolish.swift`, `RefinementVerify.swift`, `RefinementWelds.swift` | Pinned raster-refinement modules | Port the ordered clean-profile reconstruction, welding, merging, polishing, boundary sliding, and loss verification passes. Photo-mode and learned behavior remain excluded. |
| `CleanupDirection.swift`, `CleanupStraighten.swift`, `CleanupSimplify.swift`, `CleanupSnap.swift`, `CleanupInflection.swift`, `CleanupChamfer.swift`, `CleanupEven.swift`, `CleanupPipeline.swift` | Pinned typographic cleanup modules | Port cleanup order and captured defaults into deterministic Swift path transforms. Chamfer remains optional and disabled by the captured default. |
| `OutlineValidation.swift` | Pinned final point conversion plus beztrace release-gate requirements | Builds an internal neutral point model, normalizes contour starts and order, and independently fails closed on non-finite, open, degenerate, wrongly wound, intersecting, overreaching, or excessive geometry. |
| `ContourPipeline.swift` | Orchestration across pinned preprocessing and vectorization | Adds bounded internal `Data`-to-contours and `Data`-to-validated-outline composition points. It is not a public tracing API. |
| `CoreError.swift` | No direct translated file | Original beztrace error domain for decoding, resource bounds, tracing, and geometry-validation failures. |
| `BezierTraceCore.swift` | No direct translated file | Original milestone-status placeholder. Public request/result, placement, JSON/SVG, and CLI contracts remain deferred. |

Every translated source file retains the img2bez copyright and
`SPDX-License-Identifier: Apache-2.0 OR MIT` notice plus a Swift port/material
changes statement. Apple system frameworks are platform dependencies, not
bundled third-party code. No Rust dependency source was translated in either
milestone. The test-only UFO-shaped evaluator export is acceptance tooling; it
is not production UFO support or a public interface.

The corresponding differential evidence is immutable under
`Tests/Fixtures/oracle/v1`. The Swift tests compare every Basic Latin subpixel
contour, all 86 structural/fit/refinement stages, and all 62 cleaned and
validated outlines against those captures. The 24 reviewed input images must
trace twice to identical validated internal geometry.
