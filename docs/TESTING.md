# Test workflow

## Test-first rule

Phase 0 must be reproducible before Swift tracing code is added. Tests read
fixtures but never rewrite them. Fixture generation and oracle capture are
explicit maintenance operations whose diffs require review.

## Fixture corpus

The initial corpus contains 24 reviewed 1024x1024 PNG files: eight
deterministic glyphs, eight generated glyphs, four deterministic symbols, and
four generated symbols. `Tests/Fixtures/manifest.json` records source,
generation prompt, license, checksum, topology, and structural expectations.

Regenerate the deterministic half with the bundled Python runtime:

```sh
python3 scripts/generate_deterministic_fixtures.py
python3 scripts/generate_deterministic_fixtures.py --check
python3 scripts/verify_fixtures.py
```

The pinned source files live beside their license texts in
`Tests/Fixtures/sources`. Do not replace them with an unpinned web download.

## Rust reference

The only oracle is img2bez commit
`23073ca08ecdac61ad0e838bfae49a590bc2c7cc`. Its archive checksum and gate
parameters are recorded in `Tests/Fixtures/oracle/v1/reference.json`.

```sh
scripts/capture_img2bez_oracle.sh
```

The script selects Rust 1.88 by default and refuses older toolchains. The
pinned OFL source is bundled under `oracle/v1/reference-source`; before any
capture it must pass `scripts/check_reference_ufo.py`, which checks all 62
glyphs and the focused baseline's recorded on-curve counts. An override must
provide its license and provenance explicitly.

The public-history scan originally produced a false negative because it looked
for literal digit characters instead of canonical UFO glyph names (`zero`
through `nine`). After correcting that check, Virtua Grotesk commit
`797c1065abd0c1318217b7c44aff3d61074f7280` matches the complete focused
fingerprint and contains all 62 glyphs. Validate and inventory any candidate
with:

```sh
python3 scripts/intake_reference_ufo.py /absolute/path/to/reference.ufo \
  --license 'reviewed license' --provenance 'upstream delivery/revision' \
  --received YYYY-MM-DD
```

The deterministic observation-only patch is pinned at
`Tests/Fixtures/oracle/v1/reference-patches/0001-stage-capture.patch`. It is
applied only to a temporary checkout, disables parallel capture ordering, and
does not change tracing algorithms or defaults. Stage JSON formats are defined
under `Tests/Fixtures/oracle/v1/schemas`.

The 24-image Rust evidence, benchmark, and complete oracle can be checked
independently without rewriting them:

```sh
python3 scripts/verify_oracle.py
```

`--allow-incomplete` is reserved for developing a future oracle version. CI and
the normal test workflow require the complete hashed v1 manifest.

Capture, for all 62 Basic Latin glyphs, the prepared raster, subpixel contour,
structural plan, fitted outline, refined outline, cleaned outline, final JSON
and SVG, diagnostics, timing, and structural report. Store versioned immutable
results in `Tests/Fixtures/oracle/v1`; use `test-work` for transient overlays
and comparisons.

The beztrace-owned public replacement baseline pins Virtua Grotesk commit
`797c1065abd0c1318217b7c44aff3d61074f7280` under OFL-1.1. It exactly matches
the recorded focused fingerprint and establishes a measured acceptance floor
of 62/62 passing with mean structural score at least 0.961. The upstream 0.964
figure remains historical and unreproduced; it is not a release blocker.
Coordinate deviation may not exceed 0.25 canonical units before
snapping or 1 unit after snapping.

## Future Swift stages

Each implementation stage starts with unit and differential tests against the
smallest relevant immutable fixture. Public JSON and SVG tests must prove that
both serializers describe the same validated outline. Generated images are
reviewed acceptance fixtures and are never treated as exact coordinate oracles.
