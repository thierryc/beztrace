# beztrace

`beztrace` is a macOS-native tracing engine under active implementation for
converting clean raster glyph images into economical, type-design-quality
cubic Bezier outlines.

> [!IMPORTANT]
> Reference capture, the Swift tracing pipeline, neutral public API, placement,
> versioned JSON/SVG, and the standalone command-line tool are implemented and
> tested. The 100-image release-candidate input corpus is frozen and passes
> automatic topology and determinism checks; human trace acceptance remains in
> progress. Performance hardening, signed/notarized packaging, publication, and
> Glyphs MCP integration are not complete. Do not represent this local
> checkpoint as a released product.

## Intended product

The product is deliberately split into two reusable layers:

- `BezierTraceCore`, a Swift library that owns image preparation, tracing,
  placement, validation, and the neutral public result contract.
- `beztrace`, a standalone command-line tool exposing JSON/SVG tracing to local
  shell, batch, CI, and automation workflows. It is not yet packaged or signed.

beztrace is intended to become a standalone companion engine for Glyphs MCP:
it will turn raster glyphs and symbols into neutral, versioned path data that a
future Glyphs MCP adapter can apply through the existing path-mutation tools.
Glyphs MCP is a consumer, not a runtime dependency or target in this product.
No integration may begin until the standalone viability gate in
[Quality gates](docs/QUALITY_GATES.md) has passed and a versioned beztrace
release has been separately authorized.

## Planned v1 boundaries

- macOS 13 or later, Swift 6, `arm64` and `x86_64`.
- Clean, high-resolution monochrome or alpha glyph images.
- PNG and JPEG input by path or standard input.
- Canonical neutral geometry plus explicit caller-supplied placement.
- Versioned JSON and SVG output.
- No photography, arbitrary multicolor segmentation, variable-font master
  matching, UFO/GLIF writing, learned models, network access, or Glyphs.app
  dependency in v1.

The implementation is a one-time derivative Swift port of img2bez
commit `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`, licensed under
`Apache-2.0 OR MIT`. It will not automatically track later upstream changes.

## Local command-line use

Build and trace without installing anything:

```sh
swift build --configuration release
swift run --configuration release beztrace trace input.png --format json
swift run --configuration release beztrace trace input.png --format svg --output outline.svg
swift run --configuration release beztrace trace input.png --format svg \
  --svg-transform preserve --output outline-y-up.svg
```

SVG defaults to transform-free, visually upright coordinates for Sketch,
Illustrator, Figma, and similar consumers. Use `--svg-transform preserve` when
the SVG path itself must remain in the same y-up coordinates as JSON and be
rendered through an SVG group transform. JSON remains the authoritative
neutral path format for the future Glyphs MCP companion adapter.

Use `beztrace --help` for batch, inspection, tracing, placement, and SVG
transform options.
JSON schema v1 is committed at
[`Schemas/trace-result-v1.schema.json`](Schemas/trace-result-v1.schema.json).

## Repository policy

The `main` branch holds the reviewed project contract. Long-running
implementation belongs on `lit/initial-swift-port`. Changes from `main` should
be merged into that branch without rewriting its history. The implementation
branch must not be merged back until every standalone quality, performance,
licensing, and distribution gate passes.

## Project documents

- [Implementation directive](docs/IMPLEMENTATION_DIRECTIVE.md)
- [Requirements](docs/REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Interfaces](docs/INTERFACES.md)
- [Porting and licensing](docs/PORTING_AND_LICENSE.md)
- [Port map](docs/PORT_MAP.md)
- [Quality gates](docs/QUALITY_GATES.md)
- [Test workflow](docs/TESTING.md)
- [Roadmap](docs/ROADMAP.md)

## License

The project is dual-licensed under the Apache License 2.0 or the MIT
License. Ported files must preserve upstream copyright and SPDX attribution.
See [Porting and licensing](docs/PORTING_AND_LICENSE.md) and
[third-party notices](THIRD_PARTY_NOTICES).
