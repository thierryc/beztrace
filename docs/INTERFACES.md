# Standalone interfaces

This document specifies the implemented pre-release v1 contract. The contract
is exercised locally and in CI, but no signed or published release exists yet.

## Swift library

`BezierTraceCore` exposes value-oriented, sendable request/result types:

- `TraceRequest`: image bytes, trace options, and optional placement.
- `TraceOptions`: generated-image profile, threshold, inversion, minimum
  contour area, fit accuracy, smoothing, corner threshold, grid, structure
  grid, raster refinement, and deterministic diagnostic level.
- `PlacementOptions`: source box, explicit target band, sidebearing mode, and
  placement grid.
- `TraceResult`: source report, resolved options, validated outline, optional
  placement report, diagnostics, warnings, and timing breakdown.
- `Outline`, `Contour`, and `Node`: neutral serializable geometry with node
  kinds `line`, `curve`, and `offcurve`, plus smooth/corner intent.

The core entry point accepts image data, not a filesystem path. It performs no
network, filesystem, process, UI, or logging work. Call
`BezierTracer.trace(_:)` to trace, then use `TraceSerializer.json(_:)` or
`TraceSerializer.svg(_:transformMode:)` to serialize the same validated
geometry. `SVGTransformMode.bake` is the default; `.preserve` retains the
legacy y-up path plus SVG group transform. `TraceSerializer.svgPathData(for:)`
always returns y-up neutral path data and does not apply SVG presentation
policy.

## CLI

### Commands

```text
beztrace trace INPUT --format json|svg [--svg-transform bake|preserve] [--output PATH] [options]
beztrace trace - --format json|svg [--svg-transform bake|preserve] [--output PATH] [options]
beztrace batch INPUT... --format json|svg [--svg-transform bake|preserve] --output-dir DIRECTORY [options]
beztrace inspect INPUT --format json [options]
beztrace --version
```

`INPUT` is a local PNG/JPEG path or `-` for raw image bytes on stdin. Batch
input is path-only in v1. `inspect` runs preparation and tracing and returns the
same JSON result without writing a second output format. Batch processing is
deterministic, sequential, and limited to 64 inputs per invocation.

`--svg-transform` is valid only for SVG output from `trace` and `batch`. It
defaults to `bake`. Supplying it with JSON or `inspect`, or supplying a value
other than `bake` or `preserve`, is an argument error with exit code `2`.

### Trace options

- `--threshold auto|0...255`, default `auto`.
- `--invert`, default false for opaque dark-on-light input.
- `--accuracy FLOAT`, default `2.0` canonical units.
- `--smoothing FLOAT`, default `1.0`.
- `--corner-threshold FLOAT`, default `12.0` degrees.
- `--min-contour-area FLOAT`, default equivalent to 100 source pixels.
- `--grid INTEGER`, default `2`; zero disables coordinate snapping.
- `--structure-grid INTEGER`, default `0`.
- `--refine-raster` or `--no-refine-raster`, default enabled.
- `--rtl-start`, default false.
- `--diagnostics none|summary`, default `none`.

Resolved options are always reported in JSON. Invalid ranges fail before image
processing. Default output omits timing samples and is byte-stable for the same
input and options. Summary diagnostics are explicitly opt-in and may include
run-specific timing values.

### Placement options

Without placement flags, output remains in canonical neutral space: source
canvas height maps to 1088 units, coordinates are y-up, and no font metrics are
invented.

Placement requires both `--target-y-min` and `--target-y-max`, plus exactly one
horizontal mode:

- `--lsb FLOAT --rsb FLOAT`
- `--advance FLOAT --lsb FLOAT`
- `--center-in-advance FLOAT`

`--source-box canvas|ink` defaults to `ink` when placement is active. Placement
may also accept an explicit pixel rectangle in the JSON library API. The CLI
reports the complete resolved transform and metrics.

## JSON schema v1

The top-level contract is conceptually:

```json
{
  "schemaVersion": 1,
  "engine": {
    "name": "beztrace",
    "version": "0.1.0",
    "portSourceRevision": "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
  },
  "source": {
    "sha256": "...",
    "format": "png",
    "width": 1024,
    "height": 1024,
    "usedAlphaMask": true
  },
  "resolvedOptions": {},
  "pathDataVersion": 2,
  "metadataPolicy": "preserve",
  "paths": [
    {
      "closed": true,
      "nodes": [
        {"x": 10.0, "y": 20.0, "type": "line", "smooth": false},
        {"x": 12.0, "y": 30.0, "type": "offcurve", "smooth": false},
        {"x": 18.0, "y": 40.0, "type": "offcurve", "smooth": false},
        {"x": 25.0, "y": 42.0, "type": "curve", "smooth": true}
      ]
    }
  ],
  "bounds": [10.0, 20.0, 25.0, 42.0],
  "placement": null,
  "statistics": {},
  "timingsMs": {},
  "warnings": []
}
```

New geometry does not include Glyphs-specific raw node-type metadata. When
explicit placement resolves horizontal metrics, JSON additionally contains
`width`, `leftSideBearing`, and `rightSideBearing`; neutral output omits them.

Schema additions must be backward-compatible within v1. Renaming, deleting,
or changing the meaning of a field requires a new schema version.

The machine-readable schema is committed at
`Schemas/trace-result-v1.schema.json`.

## SVG

- SVG is serialized from the same final `Outline` returned in JSON.
- JSON and `TraceSerializer.svgPathData(for:)` use y-up font coordinates and
  remain the authoritative neutral geometry contract.
- `bake`, the default, reflects every line endpoint, cubic control point, and
  curve endpoint with `svgY = viewBox.minY + viewBox.maxY - jsonY`. It emits the
  path directly with no group or transform attribute, for design-tool-friendly
  import.
- `preserve` emits y-up path coordinates byte-for-byte in the legacy form and
  renders them with `<g transform="translate(0 FLIP) scale(1 -1)">`.
- Reflection does not reverse contour order or starts. Outer and counter
  winding signs reverse together in SVG coordinates and remain opposed under
  nonzero fill.
- The view box is the final geometric bounds unless explicit placement supplies
  an advance/target box.
- Paths use nonzero winding and no stroke.
- Numeric precision and contour order are deterministic.
- Metadata may identify beztrace and its version but must not embed source
  image bytes or local paths.

Changing the default to `bake` intentionally changes pre-release SVG bytes but
does not change engine version `0.1.0`, JSON schema v1, `pathDataVersion 2`, or
trace geometry because no versioned release or tag predates this correction.

## Exit codes

- `0`: success.
- `2`: invalid arguments or option combination.
- `3`: input missing, unreadable, oversized, or unsupported.
- `4`: input decoded but contained no traceable contour.
- `5`: tracing or geometry validation failure.
- `6`: output write or serialization failure.
- `7`: internal invariant failure.

Errors go to stderr as concise text by default and as versioned JSON when
`--json-errors` is requested. Stdout remains empty on failure.
