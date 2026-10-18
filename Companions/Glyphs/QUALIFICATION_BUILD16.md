# Build 16 development qualification

This is `0.2.0-dev.1`, on owner-authorized `lit/master-matching`, based on
qualified companion build 15 at `dbd7a696afda9a215c8e8a4aa42315cd799116f9`.
It is unsigned, uninstalled, unmerged and unpublished. No running document or
user font was edited; native tests create detached synthetic objects.

## Automated evidence — 2026-10-09

- Full optimized Swift suite: 110 tests, one intentional maintenance-export skip,
  no failures. The final raster winding/bounded-planning changes additionally
  pass all 10 focused matching tests.
- Full companion suite: 132 tests, including real CLI transport, frozen vector
  fixtures, detached/fake-host transactions, HOI candidate movement bounds,
  201-position candidate verification, file exchange and both raster modes.
- All 100 existing frozen tracing fixture hashes remain unchanged. Tracing
  paths, bounds, options and warnings continue to match the pinned regression
  corpus; engine version metadata is explicitly `0.2.0-dev.1`.
- Universal arm64/x86_64 engine; matching JSON is byte-equal for fixed, shared,
  winding and raster-counter cases across both slices. Packaged standalone file
  exchange and all five schema copies pass.
- Product boundaries, source SPDX headers, repository links and whitespace pass.
  Deterministic companion ZIP/manifest/payload verification passes. The original
  SDK loader pin is retained. The current scaffolder expects a newer SDK
  attribution document and is not used to replace the qualified build-15 pin.

## Detached native evidence

Official Glyphs CLI, Glyphs 4.1.1 build 4108, official Python 3.14.6; only the
application's built-in HOI tool is explicitly loaded. The repeatable probe is
`scripts/native_matching_probe.py`. Results and source-module hashes live under
`.build/glyphs-native-matching/report.json`.

Native two-layer preparation/application, names/user data/attributes, node flags,
zero width, unrelated backup layers, Undo/Redo, duplicate protection, rollback,
precision restoration, native ip calibration and committed 201-position
verification pass. Existing HOI survives a clean subsequent review. The native
panel constructs at 720 × 710 with four source modes and disabled actions when
no document is bound; this does not establish installed UI acceptance.

Save/reopen uses format v4 and explicitly measures Glyphs' storage rounding.
The observed maximum numeric deviation is 0.000437416 font units; the probe's
storage tolerance is 0.001 at its 1000 UPM. Live Apply readback remains 1e-7, and
HOI is revalidated at 201 positions after reopen. File serialization does not
preserve every floating-point bit. Master-set JSON preserves reviewed values.

## Raster comparison

`scripts/qualify_raster_matching.py` renders pinned Noto Sans at weights
400/500/600/700/800, width fixed at 100, and jointly traces the 400/800 O and H
masters. Its report is `.build/raster-variable-qualification-v2/report.json`.
Maximum extracted-boundary deviations are O 0.8322/0.8028 and H
0.2366/0.1972 font units, below the 1-unit fitting limit. Intermediate binary
mask disagreement is measured at all five positions: at most 1.74% of ink for O
and 3.31% for H. These measurements include rasterization and the source font's
own variation behavior; they are not native HOI verification or a continuous
interpolation guarantee. Counter winding is covered by a regression assertion.

## Outstanding acceptance gates

Visible installed menu/panel flow, all native cancellation/stale-target cases,
real designer acceptance, native raster canvas placement and import into another
font remain pending. So do compiled-font interpolation, expanded performance
and robustness, the full architecture matrix, and distribution gates.

Detached CLI export failed: `Couldn’t open GlyphNames file (error:2)`; the CLI
export subcommand also could not determine the source document type. No font
binary was qualified. The native source save/reopen probe succeeds. Resolve
export in the authorized native qualification environment; do not infer success
from CLI exit status or a returned generation object.

Installation, relaunch, live font edits, signing/notarization, merge and
publication retain the separate authorizations in the root AGENTS.md. Build 16
is a reviewable development candidate, not an accepted usable milestone.

## Post-package LeftyNote experiment

The owner subsequently authorized a disposable LeftyNote copy and generated
bold glyph images. The [experiment report](../../docs/LEFTYNOTE_MATCHING_EXPERIMENT.md)
records matching, native canvas capture, Undo/Redo and save/reopen for a/n/o,
the source-g rejection, Swift improvements and remaining point-economy and
cross-architecture serialization failures. These later changes do not qualify
or replace the existing build-16 archive bytes. Installed UI and compiled-font
export remain pending.
