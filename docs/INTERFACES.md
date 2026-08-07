# Planned interfaces

This document specifies the intended v1 contract. It is not evidence that an
implementation exists.

## Swift library

`BezierTraceCore` will expose value-oriented, sendable request/result types:

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
network, filesystem, process, UI, or logging work.

## CLI

### Commands

```text
beztrace trace INPUT --format json|svg [--output PATH] [options]
beztrace trace - --format json|svg [--output PATH] [options]
beztrace batch INPUT... --format json|svg --output-dir DIRECTORY [options]
beztrace inspect INPUT --format json [options]
beztrace --version
```

`INPUT` is a local PNG/JPEG path or `-` for raw image bytes on stdin. Batch
input is path-only in v1. `inspect` runs preparation and tracing and returns the
same diagnostics without writing a second output format.

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

Resolved options are always reported in JSON. Invalid ranges fail before image
processing.

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

## SVG

- SVG is serialized from the same final `Outline` returned in JSON.
- The view box is the final geometric bounds unless explicit placement supplies
  an advance/target box.
- Paths use nonzero winding and no stroke.
- Numeric precision and contour order are deterministic.
- Metadata may identify beztrace and its version but must not embed source
  image bytes or local paths.

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
