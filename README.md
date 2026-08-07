# beztrace

`beztrace` is a planned macOS-native tracing engine for converting clean raster
glyph images into economical, type-design-quality cubic Bezier outlines.

> [!IMPORTANT]
> This repository is documentation-only. It contains no Swift package, tracing
> engine, executable, MCP adapter, or production artifact. Do not represent it
> as working software.

## Intended product

The product is deliberately split into two reusable layers:

- `BezierTraceCore`, a Swift library that owns image preparation, subpixel
  contour extraction, structural analysis, cubic fitting, raster refinement,
  typographic cleanup, placement, validation, and serialization.
- `beztrace`, a signed command-line tool that exposes the library to local
  shell, batch, CI, and automation workflows.

Glyphs MCP is a possible future consumer, not part of this product. No Glyphs
integration may begin until the standalone viability gate in
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

The planned implementation is a one-time derivative Swift port of img2bez
commit `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`, licensed under
`Apache-2.0 OR MIT`. It will not automatically track later upstream changes.

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
- [Quality gates](docs/QUALITY_GATES.md)
- [Roadmap](docs/ROADMAP.md)

## License

The planned project is dual-licensed under the Apache License 2.0 or the MIT
License. Ported files must preserve upstream copyright and SPDX attribution.
See [Porting and licensing](docs/PORTING_AND_LICENSE.md) and
[third-party notices](THIRD_PARTY_NOTICES).
