# Architecture

## Product shape

```text
Image bytes/path
      |
      v
BezierTraceCore
  Raster -> Iso-contours -> Structure plan -> Cubic fit
         -> Raster refinement -> Typographic cleanup
         -> Placement -> Validation -> TraceResult
      |
      +------------------+
      |                  |
      v                  v
Versioned JSON          SVG
      ^
      |
beztrace CLI (single, batch, inspect)
```

`BezierTraceCore` is the only owner of tracing and geometric behavior. The CLI
owns argument parsing, filesystem and stream I/O, process exit codes, logging,
batch orchestration, and serializers selected by the user. Future consumers
must call the versioned library or CLI contract rather than duplicating trace
logic.

## Planned package products

- `BezierTraceCore`: public Swift library.
- `beztrace`: executable depending only on `BezierTraceCore` and Apple system
  frameworks.

No Glyphs-specific target, MCP server, daemon, XPC service, plugin, or GUI is
part of v1.

## Core subsystems

### Geometry

Local value types represent points, vectors, affine transforms, lines, cubic
segments, contours, outlines, bounds, node kinds, split kinds, and placement
reports. Geometry uses `Double`, explicit tolerances, deterministic comparison,
and no UI framework types in public results.

### Raster preparation

ImageIO/CoreGraphics decode supported images. Preparation normalizes
orientation, dimensions, alpha/coverage, grayscale, inversion, threshold,
low-resolution recovery, and clean-profile smoothing. Accelerate/vImage may be
used for bounded pixel operations where it measurably improves speed without
changing reference behavior.

### Subpixel contours

Marching squares extracts the threshold iso-line with interpolated edge
crossings. The subsystem assembles closed contours, rejects frame/noise
artifacts, calculates bounds/area, resamples by arc length, and supplies stable
point order.

### Structural planning

Curvature and geometric evidence identify corners, straight runs, tangent
boundaries, x/y extrema, inflections, and safe split locations. The plan is an
explicit intermediate value so it can be tested independently from fitting.

### Cubic fitting

Each planned section becomes a line or one constrained cubic when possible.
The fitter solves handle lengths under required tangent directions and adds
fitter joints only when error limits require them. Join smoothing and
harmonization preserve intentional corners.

### Raster refinement

The refinement stage compares candidates with source coverage in a bounded
band around the outline. It may rebuild known raster artifacts, merge
fitter-created joints, polish handles, rebalance, slide line/curve boundaries,
and verify coverage while preserving design joints.

### Typographic cleanup

Ordered passes normalize direction, straighten deliberate runs, remove
redundant points, snap grids and eligible H/V handles, anchor inflections,
reconstruct corners, even/cap handles, and round deterministically.

### Placement and validation

Tracing remains neutral. Optional placement consumes explicit caller intent.
Validation checks finite values, topology, closure, winding, degeneracy,
self-intersection, handle reach, counts, and serialization invariants before a
result leaves the core.

## Concurrency and performance

- Raster preparation is bounded and may use Accelerate.
- Independent contours may fit/refine concurrently, but final results are
  sorted by deterministic geometric keys.
- Batch concurrency is controlled by the CLI and must cap memory.
- No mutable global configuration, caches affecting results, environment-based
  tuning, or timing-dependent decisions are allowed in production behavior.

## Dependency policy

V1 may use Swift Standard Library, Foundation, ImageIO, CoreGraphics,
CoreFoundation, Accelerate, and system cryptographic/hash facilities. Any new
third-party source or binary dependency requires a requirements change,
license/provenance audit, SBOM entry, binary-size review, and reproducibility
review before adoption.
