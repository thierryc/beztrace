# Roadmap

## 0. Documentation bootstrap

- Establish this documentation-only repository on `main`.
- Create `lit/initial-swift-port` at the same baseline.
- Do not add Swift or publish a remote repository.

Completion: project contract is internally consistent, links resolve, licenses
are present, and both branches point to the documentation baseline.

## 1. Reference capture

- Freeze the pinned img2bez baseline and evaluation environment.
- Capture stage fixtures, end-to-end results, structural scores, timings and
  reference licenses.
- Establish the generated-image corpus and review rubric.

Completion: the oracle and scoring loop run without beztrace implementation.

## 2. Swift core foundations

- Add the Swift package on `lit/initial-swift-port` after authorization.
- Implement geometry, raster preparation, iso-contours and deterministic
  intermediate types with unit and differential tests.

Completion: prepared rasters and contour fixtures match the oracle.

## 3. Structural fitting

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

Only after viability may another project prepare its own integration plan. A
future Glyphs MCP adapter is expected to be read-only, accept path or base64
input, invoke a checksum-pinned signed executable, return path data compatible
with `pathDataVersion 2`, and leave application to the existing path mutation
tool. None of that integration is part of this repository's initial work.
