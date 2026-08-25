# Porting and licensing policy

## Source baseline

The only authorized img2bez source baseline is:

- Repository: `https://github.com/eliheuer/img2bez`
- Commit: `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`
- Package version at review: `0.1.0`
- Declared license: `Apache-2.0 OR MIT`
- Copyright header: `Copyright 2026 the img2bez Authors`

The baseline must be archived or checksum-recorded before implementation so
future upstream changes cannot silently enter the port.

The file-level translation inventory and material differences are recorded in
[Port map](PORT_MAP.md).

## Nature of the work

beztrace is a permitted derivative translation and adaptation of img2bez's
procedural tracing pipeline. It is not a legal clean-room implementation.
Changing the implementation language does not remove upstream attribution or
license obligations.

The beztrace repository and ported files remain available under
`Apache-2.0 OR MIT`. Each translated source file must retain:

```text
Copyright 2026 the img2bez Authors
SPDX-License-Identifier: Apache-2.0 OR MIT
```

and add a concise statement that the file was ported to Swift and materially
modified for beztrace. New original files should identify beztrace contributors
and use the same SPDX expression unless a documented reason requires otherwise.

## Included behavior

The port includes only behavior required for the standalone clean generated-
glyph product:

- Bitmap preparation and threshold resolution.
- Subpixel iso-contours.
- Structural feature planning.
- Constrained line/cubic fitting.
- Raster-loss refinement.
- Typographic cleanup, placement, validation, JSON, and SVG concepts.

## Excluded behavior

- Rust CLI presentation and Cargo feature machinery.
- UFO, GLIF, norad, and font-source writing.
- Multi-master joint planning.
- WASM bindings.
- Learned decision heads.
- Comparison-image renderer and upstream release tooling.
- Photo/scan profiles in v1.

Exclusion does not authorize weakening the core fitting and cleanup behavior.

## Dependency provenance

img2bez depends on projects such as `image`, `imageproc`, `kurbo`, `norad`,
`rayon`, `serde`, `tiny-skia`, and others. Their licenses do not automatically
become irrelevant merely because beztrace is written in Swift.

- Do not translate dependency implementation code while porting img2bez-owned
  modules.
- Replace image decoding and common geometry with Apple system frameworks and
  independently written local primitives.
- If a dependency implementation must be consulted or adapted, pause, record
  the exact file/revision/license, determine compatibility, preserve required
  notices, and update `THIRD_PARTY_NOTICES` and the SBOM before proceeding.
- Public mathematical methods may be independently implemented, but cited
  papers, sample code, and reference implementations still require provenance
  and license review.

## One-time fork policy

After the pinned port begins, beztrace does not follow upstream releases. A
later img2bez change may be studied only through a separately reviewed proposal
that identifies provenance, motivation, tests, and licensing. It must enter as
a deliberate beztrace change, never as an automatic synchronization.

## Distribution obligations

Every source and binary distribution must include both license texts, retained
copyright/SPDX notices, this provenance, relevant third-party notices, and an
SBOM matching the actual artifact. Modified files must identify material
changes. Release verification must confirm that licenses and notices are inside
both the ZIP and installer payload.

This document records project policy and is not legal advice.
