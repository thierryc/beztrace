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

## 3. Structural fitting — next

- Implement structural planning, constrained cubics, fallback subdivision,
  join correction and raster-loss refinement.
- Port cleanup and validation in the required order.

Completion: the 62-glyph differential topology and numeric gates pass.

## 4. Standalone interfaces

- Stabilize `BezierTraceCore`.
- Implement JSON schema v1, SVG, trace, batch, inspect, streams and exit codes.
- Complete malformed-input, determinism and generated-corpus testing.

Completion: the public interface and quality gates pass without Glyphs.

## 5. Performance and release hardening

- Optimize measured bottlenecks without changing output.
- Build and validate universal artifacts.
- Prepare SBOM, licenses, checksums, Developer ID signing, notarization and the
  installer package.
- Validate a real non-Glyphs workflow.

Completion: every standalone viability gate passes. Signing, publishing, and
remote creation still require explicit authorization.

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
