# Implementation directive

## Objective

Build a fast, deterministic Swift engine that converts a clean generated glyph
image into a small, editable, type-design-quality cubic Bezier outline. A
successful trace preserves visible ink while making structural decisions a
type designer would expect: intentional corners and lines, on-curves at
meaningful extrema and inflections, smooth tangent continuity, economical
point counts, correct winding, and stable placement.

The implementation is a one-time behavior-compatible port of the procedural
img2bez pipeline pinned in `PORTING_AND_LICENSE.md`. It is not a generic image
vectorizer and must not be reduced to edge detection followed by polygon
simplification.

## Required phase order

### Phase 0: freeze the reference

1. Record the pinned img2bez source tree, license files, relevant configuration
   defaults, reference commands, and compiler/runtime environment.
2. Produce immutable stage fixtures and end-to-end JSON results from the Rust
   reference for the 62-glyph Basic Latin corpus.
3. Define coordinate, path direction, node ordering, rounding, error, and
   timing measurement conventions before porting behavior.
4. Establish generated-image fixtures and their review provenance.

Exit condition: reference outputs and scoring tools reproduce the documented
baseline without any Swift tracing code.

### Phase 1: foundations and raster preparation

1. Add the Swift package only after implementation is separately authorized.
2. Implement local geometry primitives, transforms, bounds, cubic evaluation,
   derivatives, distance calculations, and deterministic serialization.
3. Decode PNG/JPEG with ImageIO/CoreGraphics, normalize orientation and color,
   use meaningful alpha as a mask, and otherwise produce grayscale coverage.
4. Implement thresholding, inversion, low-resolution handling, speckle limits,
   and the clean generated-image profile.

Exit condition: raster and geometry unit fixtures match the reference within
documented numeric tolerances on both architectures.

### Phase 2: subpixel contours and structural planning

1. Port marching-squares iso-contour extraction with subpixel interpolation.
2. Filter image-frame artifacts and undersized contours deterministically.
3. Resample by arc length and smooth the curvature signal without erasing
   intentional features.
4. Detect and classify corners, straight runs, tangent points, x/y extrema,
   inflections, and fitter-created joints.
5. Normalize contour starts and outer/counter direction.

Exit condition: contour topology and structural split fixtures match the
pinned Rust oracle.

### Phase 3: cubic fitting and refinement

1. Implement constrained line and cubic section fitting with fixed tangent
   directions where structure requires them.
2. Subdivide only when the allowed error cannot be met by one cubic.
3. Align G1 joins and harmonize eligible joins for G2-like visual continuity.
4. Implement raster-loss scoring and bounded refinement of handle lengths and
   fitter-created structures.
5. Preserve design joints while merging redundant fitting joints.

Exit condition: node types, segment counts, tangent classifications, and
coordinates pass the differential tolerances.

### Phase 4: typographic cleanup and validation

1. Reconstruct sharp corners and remove raster-rounded slivers.
2. Straighten deliberate stems and flats; do not flatten gentle optical arcs.
3. Remove redundant points without removing meaningful extrema.
4. Snap coordinates and eligible H/V handles, split real inflections, even and
   cap handles, and apply deterministic rounding.
5. Reject non-finite coordinates, degenerate segments, invalid direction,
   unexpected open contours, and self-intersections.

Exit condition: every reference and generated fixture yields valid,
economical, editable geometry.

### Phase 5: library and CLI contracts

1. Stabilize the pure `BezierTraceCore` request/result API.
2. Implement JSON schema v1 and SVG serialization from the same final outline.
3. Add the `trace`, `batch`, `inspect`, and `--version` CLI surfaces.
4. Keep stdout machine-readable, diagnostics on stderr, stable exit codes, no
   network access, and deterministic batch ordering.
5. Implement neutral canonical output and caller-supplied placement without
   glyph-name or typography inference.

Exit condition: documented interface compatibility tests pass and JSON/SVG
geometry is equivalent.

### Phase 6: hardening and standalone release

1. Complete malformed-input, determinism, fuzz/property, timeout, resource,
   architecture, and package-installation coverage.
2. Meet every score and performance gate in `QUALITY_GATES.md`.
3. Produce licenses, provenance, SBOM, checksums, universal build, signed ZIP,
   and signed/notarized installer package.
4. Validate at least one real non-Glyphs workflow using only the released CLI.

Exit condition: the viability review explicitly approves merging the
implementation branch. Publication still requires separate authorization.

## Prohibited shortcuts

- Do not ship Vision contours, CoreGraphics path simplification, Ramer-Douglas-
  Peucker polygons, or another generic tracer as a substitute for the required
  fitting pipeline.
- Do not declare success based only on raster similarity. Structure, point
  economy, extrema, tangents, winding, validity, and editability are mandatory.
- Do not remove raster refinement or typographic cleanup to meet speed goals.
- Do not hide invalid geometry behind SVG rendering tolerance.
- Do not use Python or Glyphs APIs inside the production Swift core.
- Do not add network downloads, telemetry, automatic updates, or remote input
  URLs in v1.
- Do not implement Glyphs MCP integration before standalone viability.
