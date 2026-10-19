# Companion 0.2.0/build 25 — qualification history

Current status: **signed, Apple-notarized and published on 2026-10-18**. See the
[final release record](../../docs/RELEASE_0.2.1.md) for signed distribution checks
and the explicit native Intel waiver. The original unsigned acceptance record
below is preserved as historical evidence.

## Unsigned local native acceptance — 2026-10-17

Date: 2026-10-17. Source:
`217dcc0aad50a4c4a6b7e8c65e6bacc0931e2054`.
Backend: standalone engine 0.2.1, selected explicitly; system engine unchanged.
Host: Apple M1 Max, macOS 26.7.1, Glyphs 4.2/build 4202, official Python 3.14.
Status: **unsigned local candidate, installed and tested on Apple Silicon**.
It is not a published or distribution-qualified release.

## Passed acceptance

- The installed plugin matches all 56 packaged payload files. Both unsigned
  packages reproduce byte-for-byte from the clean frozen source.
- Actual installed UI actions pass in Single image, Images → masters,
  Image → path and Paths → masters. Preview and committed coordinates agree;
  widths, anchors, image crop and affine placement stay protected.
- Reference-locked smoothing changes only two target handles in the controlled
  12-node pair. Original-source error is bounded by 0.79007892376946 units at a
  1-unit tolerance. Reference objects, on-curves, node counts/order/types/flags
  stay unchanged. The same 12 benchmark jobs retain geometry, full reports,
  bounds and refusals, with identical arm64/Rosetta JSON.
- An uninterrupted native UI Undo/Redo cycle preserves geometry and live hint
  settings, custom userData and explicit node attachments. Injected application
  failures and deliberate metadata corruption restore both masters and hint data
  with balanced undo groups. Settings changes, cancellation and stale sources
  revoke Apply; a fresh preview restores eligibility.
- Fresh-file save/reopen preserves supported geometry, node flags and hint
  attachments/settings. Native storage rounding remains within the original
  1-unit source budget for the controlled smoothing case: conservative bound
  0.7902403396970586 units after rounding.
- A neutral standalone packet imports into a detached recipient and round-trips
  with identical geometry and explicit axis confirmation.
- Native variable TTF export passes structural parsing and 201 interpolation
  positions for each of three matching workflows (603 checks). Maximum coordinate
  interpolation rounding is 0.003692 units. This is bounded topology/interpolation
  evidence, not a full font or shaping audit.
- All 27 local source commands pass, including sanitizer, 194 Swift tests per
  architecture (two intentional skips each), and 180 companion tests.

All fonts used here are disposable fixtures, preserved and closed after testing.
No user font was modified. The grouped sidebar was visually inspected.

## Performance scope

Five tracing fixtures, three warmups and 30 measurements give worst process p95
759 ms and peak RSS about 30 MB. A separate warm native copy/staging profile
covers up to 1,001 glyphs / 46,008 total nodes while holding the selected glyph
at four nodes per master: maximum staging 18.1 ms, or 25.2 ms including release.
Two installed UI stages of the selected 12-node case took 45.2 and 22.1 ms.
These samples do not establish general app latency or native Intel performance.

## Limitations and remaining gates

- A non-collinear smooth join in a fixed reference cannot be repaired by moving
  target handles alone. The R raster control correctly refuses with smoothing
  enabled; smoothing off succeeds at the same fitting tolerance. Apply stays
  disabled on refusal. Error limits are never raised automatically.
- Native HOI is a separate opt-in, gated to Glyphs build 4108. It is hidden and
  unqualified on build 4202. Joint smoothing does not establish native HOI support.
- Glyphs' file writer omits custom GSHint userData, including on the untouched
  control glyph. Live Apply/Undo/Redo preservation does not imply file persistence
  for that custom dictionary.
- Headless undo-group failures and recovery-copy fixtures that lost native
  metadata are retained as excluded trials. They are not fresh-file or UI passes.
- Native Intel remains untested; Rosetta is separate evidence. The historical
  build-15 waiver does not cover this candidate.
- Signing/notarization and signed installation/update/rollback/removal,
  Gatekeeper, final distribution checks and publication remain pending approval
  and completion. Production graph selection stays deferred.

## Evidence locations

The local packet `.build/release-0.2.1-companion-0.2.0-build25/` contains the
review, reproducible ZIPs, manifests, SPDX inventories, SHA256SUMS and copied
qualification receipts. Native originals are in `.build/native-build25-installed/`;
the final same-benchmark report is
`test-work/release-0.2.1-companion-0.2.0-build25/integration-comparison.json`.
These ignored local paths are audit evidence, not public release URLs.

The [engine/companion record](../../docs/RELEASE_0.2.1.md) lists archive hashes
and remaining release gates. Published engine 0.2.0, companion 0.1.0/build 15,
and all earlier release tags and asset bytes remain unchanged.

## Signed 0.2.0/build 25 release — 2026-10-18

The owner authorized signing, Apple notarization and publication and explicitly
waived native Intel testing for engine 0.2.1 and companion 0.2.0/build 25.
Both signed distributions pass their final installation/lifecycle checks.
Actual signed UI Apply/Undo/Redo on Glyphs 4.2/build 4202 preserves the exact
reference, node structure, widths and live hint metadata/attachments. Rollback
to published signed build 15, removal and reinstallation pass. The shared engine
is unchanged. Earlier unsigned statuses and failed trials above are historical.
See the [final release record](../../docs/RELEASE_0.2.1.md) and
[public qualification receipt](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.0/qualification.json).
Native Intel remains untested, owner-waived; native HOI on 4202 remains unqualified.
