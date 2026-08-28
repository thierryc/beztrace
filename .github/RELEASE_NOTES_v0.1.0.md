# beztrace 0.1.0

The first standalone release of beztrace converts clean raster glyphs and
simple monochrome symbols into economical, editable cubic Bezier outlines.

Highlights:

- Native Swift tracing pipeline for macOS 13 or later.
- Universal `arm64` and `x86_64` executable.
- Canonical Y-up JSON schema v1 with `pathDataVersion 2`.
- Transform-free SVG output by default, plus a Y-up preserve mode.
- Single-image, stream, inspection, and deterministic batch workflows.
- Developer ID signing, Apple notarization, checksums, and SPDX 2.3 SBOMs.
- Validated against the pinned img2bez reference and a reviewed 100-image
  glyph/symbol corpus.

The notarized PKG is the recommended installation method. Download the PKG and
`SHA256SUMS`, verify the hashes, install, then run:

```sh
beztrace --version
```

Glyphs.app and Glyphs MCP integration are not included in this release. The
versioned neutral JSON output is designed for a future companion adapter.
