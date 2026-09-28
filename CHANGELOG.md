# Changelog

## 0.1.1-dev.1 — local development, unreleased

- Preserve small closed contours through smoothing and fitting, including
  loops whose endpoints coincide and contours formed by two cubic segments.
- Compute winding from cubic geometry instead of the endpoint polygon.
- Add synthetic regressions; retain JSON schema v1 and pathDataVersion 2.
- Glyphs companion build 6 accepts this local engine and released 0.1.0,
  verifying that result and executable versions match.

No release, Developer ID signing, notarization or system installation accompanies
this development version. See `docs/SMALL_CONTOUR_FIX.md` for local verification.

## 0.1.0 — 2026-08-27

First standalone release.

- Added deterministic PNG/JPEG preparation for clean monochrome glyphs and
  symbols.
- Added subpixel contour extraction, structural planning, constrained cubic
  fitting, raster refinement, typographic cleanup, and fail-closed validation.
- Added the neutral Swift API, JSON schema v1, and `pathDataVersion 2`.
- Added transform-free baked SVG and Y-up preserve SVG modes.
- Added `trace`, `batch`, and `inspect` command-line workflows.
- Added universal Apple Silicon and Intel distribution, Developer ID signing,
  Apple notarization, SPDX SBOMs, checksums, and package installation.

Glyphs.app and Glyphs MCP integration are deliberately not included. They are
future consumers of the neutral JSON contract.
