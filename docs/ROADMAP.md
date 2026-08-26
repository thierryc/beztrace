# Roadmap

## 0. Documentation bootstrap — complete

- Establish this documentation-only repository on `main`.
- Create `lit/initial-swift-port` at the same baseline.
- Do not add Swift or publish a remote repository.

Completion: project contract is internally consistent, links resolve, licenses
are present, and both branches point to the documentation baseline.

## 1. Reference capture — complete

- Freeze the pinned img2bez baseline and evaluation environment.
- Capture stage fixtures, end-to-end results, structural scores, timings and
  reference licenses.
- Establish the generated-image corpus and review rubric.

Completion: the oracle and scoring loop run without beztrace implementation.

The completed public replacement baseline uses Virtua Grotesk commit
`797c1065abd0c1318217b7c44aff3d61074f7280`: 62/62 glyphs pass with a measured
mean structural score of `0.961`.

## 1A. Stabilize checkpoint — complete

- Sanitize and commit the immutable fixtures, oracle, tooling, and provenance.
- Enforce the complete reference checkpoint in CI.
- Verify the committed state from a clean local worktree.

Completion: the branch is clean, the checkpoint is locally committed, and all
strict reference checks pass without rewriting fixtures.

## 2. Swift core foundations — complete

- Add the Swift package on `lit/initial-swift-port` after authorization.
- Implement geometry, raster preparation, iso-contours and deterministic
  intermediate types with unit and differential tests.

Completion: 28 Swift tests pass on `arm64` and `x86_64`; all 62 Basic Latin
subpixel contours match the pinned oracle point-for-point within `1e-9`, and
all 24 reviewed images produce their declared raw contour topology.

## 3. Structural fitting — complete

- Implement structural planning, constrained cubics, fallback subdivision,
  join correction and raster-loss refinement.
- Port cleanup and validation in the required order.

Completion: all 86 captured contours match the pinned structural plans,
initial fits, and raster-refined fits; all 62 cleaned and validated outlines
match their captured structure and numeric gates; and the test-only evaluator
reports 62/62 passing with a `0.964` mean structural score. All 24 reviewed
glyph and symbol images trace twice to identical, validated internal outlines.

## 4. Standalone interfaces — complete

- Stabilize `BezierTraceCore`.
- Implement JSON schema v1, SVG, trace, batch, inspect, streams and exit codes.
- Complete malformed-input, determinism and generated-corpus testing.

Completion: the byte-stable neutral Swift API, explicit placement, JSON schema
v1, SVG, `trace`, `batch`, `inspect`, standard streams, diagnostics, and stable
exit codes pass without Glyphs. The optimized suite runs 73 tests with one
explicit maintenance-only skip and zero failures on Apple Silicon and local
x86_64 under Rosetta; native Intel remains enforced by CI.

Pre-release interoperability correction: SVG now has explicit `bake` and
`preserve` transform modes. Bake is the transform-free default for design
tools; preserve retains the legacy y-up path plus rendering transform. JSON,
raw SVG path data, schema v1, `pathDataVersion 2`, and traced outlines are
unchanged.

## 5. Performance and release hardening — in progress

- Optimize measured bottlenecks without changing output.
- Build and validate universal artifacts.
- Prepare SBOM, licenses, checksums, Developer ID signing, notarization and the
  installer package.
- Validate a real non-Glyphs workflow.

Completion: every standalone viability gate passes. Signing, publishing, and
remote creation still require explicit authorization.

Current checkpoint: the source corpus is frozen at 100 images (50
deterministic and 50 generated; 64 glyphs and 36 symbols). The project owner
selected all 38 newly generated sources, their original and normalized hashes
are pinned, and all 100 inputs pass repeated optimized tracing with the
declared contour counts. The complete optimized suite passes 82 tests on both
Apple Silicon and x86_64/Rosetta with one maintenance-only skip, and JSON is
byte-identical across those architectures for all 100 inputs. Trace-quality
review of the newly selected sources is still pending. Same-machine Swift/Rust
relative timing and peak RSS pass; the
absolute one-second CLI p95 gate remains red on four of five benchmark inputs.
An unsigned universal release candidate, SBOM, checksums, and package tooling
exist locally. Signing, notarization, and installation remain outside the
currently authorized identity boundary.

## 6. Viability review

- Review implementation, fixtures, benchmark evidence, security, licensing,
  package behavior and documentation.
- Approve or reject merge of `lit/initial-swift-port` into `main`.
- If approved and separately authorized, publish the first versioned release.

Completion: beztrace is independently viable and consumable.

## 7. Future consumers

The intended consumer is a future Glyphs MCP companion integration. Only after
viability may that project prepare its adapter: accept path or base64 input,
invoke a checksum-pinned signed executable, return path data compatible with
`pathDataVersion 2`, and leave application to the existing path-mutation tool.
None of that integration is part of this repository's initial work.
