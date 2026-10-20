> Next release: **0.2.1/build 26** with engine **0.2.2**, under qualification.
> Both target macOS 13+ and arm64/x86_64. Native Intel is untested, owner-waived.
> [Release record](../../docs/RELEASE_0.2.2.md). Published build 25 remains unchanged.

# Beztrace for Glyphs

A small native panel that traces the image already placed in Glyphs.
**0.2.0 build 25** provides the four-mode dialog, grouped settings, verified joint
smoothing and hint-preserving matching. Ordinary tracing retains compatibility
with separately installed **beztrace 0.1.0 or 0.1.1** engines
or local **0.1.1-dev.1** through **0.1.1-dev.4** development engines,
JSON schema **1**, and path data **2**. The new matching panel requires the separately released **0.2.1** engine.

[Signed release 0.2.0/build 25](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.2.0)
is Developer ID signed and Apple-notarized. Native qualification covers Apple
Silicon / Glyphs 4.2/build 4202, including signed UI Apply/Undo/Redo and signed
update/rollback/removal/reinstallation. The unchanged Python source also passes
all four modes, fresh-file exchange and 603 compiled interpolation checks.
Native Intel is untested and explicitly owner-waived for this release.
Install the separately released engine 0.2.1 for matching, then open the plugin
and relaunch Glyphs. See [build 25 qualification](QUALIFICATION_BUILD25.md) and
the [release record](../../docs/RELEASE_0.2.1.md).

### Match Masters

Point growth is bounded. **Extra on-curves** defaults to zero; enter an explicit
allowance such as 2 for shared subdivision. **Max total nodes** includes handles
and starts at 125% of the selected reference's node count. A result over either
limit is rejected before Apply. Import rechecks the receiving limits, including
older files. Line-to-cubic conversion preserves shape but adds handles within
the total ceiling. Joint image tracing uses absolute limits.

Select one glyph in a font with exactly two ordinary masters and one axis, then
choose **Path → Beztrace Match Masters…**. The currently selected master is the
**Target**. The **Reference** starts at the previous master (the other master in
this two-master workflow), preferring the last selection when available.

The 820 × 620 native dialog starts with four labeled icon modes:

- **Single image** prepares a detached trace of the selected layer's canvas image.
  **Image** groups quality, threshold and inversion; **Curves** groups accuracy,
  smoothing, corner sensitivity, grid, speck removal and raster refinement. **Apply to Layer**
  appends the reviewed paths with Undo. One master and background destinations
  remain supported; master matching restrictions do not apply to this mode.
- **Images → masters** jointly traces the two masters' canvas images. Fit tolerance
  and the total node ceiling sit in **Fitting**, beside an **Image** group.
- **Image → path** fits the target canvas image to the reference outline. Fit
  tolerance and the total node ceiling sit in **Fitting**. **Reference**, **Image**
  and **Correspondence** expose the relevant settings. Additional on-curves appears
  only for shared subdivision; contour/start selectors appear only with
  **Manual correspondence** selected.
- **Paths → masters** matches the existing outlines. The inspector omits image
  controls. **Reference**, **Fitting** and **Correspondence** expose reference policy
  and review of existing compatible structure. Review hides manual overrides.

Paired modes show **Smooth compatible joins**, enabled by default, beside Fit
tolerance and Node limit. It adjusts target handles within the same fit tolerance,
preserves the reference and all on-curves, and keeps node counts, order, types and
flags. A refusal blocks the preview/Apply result; limits are never raised. The
engine measures against the original vector or placed raster boundary, including
after fitting. Single-image tracing retains its existing behavior.

This step requires a locally built engine advertising `matchSmoothingVersion: 1`
and `hybridFittingVersion: 1`; the earlier published matching preview does not
provide this addition. Source-checkout builds select
`.build/beztrace-0.2.1/bin/beztrace`. Build it locally with
`python3 scripts/build_development_engine.py --output .build/beztrace-0.2.1`,
or select the verified development executable through **Additional actions… → Choose engine…**.

**Native HOI correction** is a separate opt-in in **Interpolation** on a supported
Glyphs build; its threshold and shape-movement controls appear only when selected.
Joint smoothing does not claim native HOI verification. Existing HOI is preserved;
geometry changes that would invalidate it are refused. Imported native corrections
require native verification. Imported geometry retains its recorded smoothing
choice; that control is read-only during import review. Fit and kink thresholds are measured per 1000 em.
Total nodes include cubic handles. Production graph selection remains deferred.

**Update Preview** is always a secondary button with the two-arrow refresh icon.
It is enabled for a new job or when sources, settings or the engine have changed;
while a current result is available it is disabled. It never writes to the font.
A change leaves the last preview visible but disables **Apply to Masters** until
an updated result passes validation. No repeated “preview needs updating” notice
is shown. Display tabs, the interpolation slider and no-op settings events do not invalidate a result. Errors and actionable refusals still
appear below the preview; Error Details is in Additional actions…. Source changes also
invalidate Apply, and the existing application APIs revalidate again before writes.

The primary accent and Return key belong to Apply only when a current, valid
proposal is available. Cancel cancels an active job; when idle it closes the panel.
Overlay, Side by side and Interpolation share one preview canvas. The inspector
scrolls when visible settings need extra room without enlarging the window.
There is no global Advanced disclosure. **Additional actions…** holds Import, Export, engine selection and
**Use current glyph**. Error Details appears there only for a failure.
Reopening either menu captures the current selection. Matching application retains
one two-master Undo transaction, exact readback and verified recovery. Widths,
anchors, guides, canvas images and backup layers remain untouched. Components
and intermediate layers are rejected by paired modes. Hints do not block previews.
Before Apply, hints on changed paths must have explicit, unambiguous node
correspondence; their settings and mapped references are preserved. Hints on
unchanged paths remain attached to the original nodes. If an affected attachment
cannot be preserved, Apply is refused while the preview remains available.

**Import…** maps a standalone master-set JSON to the selected layers with explicit
axis confirmation. **Export…** writes the reviewed geometry and optional native HOI;
receiving Glyphs always samples imported corrections again. No font is created or
saved automatically. Raster Threshold accepts `auto` or 0–255; Invert is separate.
The raster planner uses smoothing 1, corner threshold 12 and minimum contour area
100 in the neutral 1088-height canvas, recorded with source evidence. Fit tolerance
is measured in font units against the extracted source boundary.

Automatic HOI is enabled only on recorded Glyphs build **4108**. New corrections
use intermediate points and preserve existing settings. The report distinguishes
detection threshold, endpoint-based verification limit and maximum shape movement.
Native verification samples 101 regular and 100 interleaved locations.

Build 25 passes the bounded installed-native acceptance described above.
Some raster references have non-collinear smooth joins and cannot be repaired
with the reference fixed. A smoothing refusal disables Apply; switch off
**Smooth compatible joins** to review the fitted result at the same error limit.
The original source remains the measurement baseline. Glyphs' file writer omits
custom hint userData even on untouched control glyphs; live hint preservation
does not promise file persistence for that dictionary. See
[master matching](../../docs/MASTER_MATCHING.md) for contracts and acceptance gates.

## Use it

1. Place and position a PNG/JPEG on one glyph layer using Glyphs' native image tools.
2. Choose **Path → Beztrace…** for Single image, or **Beztrace Match Masters…** for
   the paired workflows. Both menu items open the same four-mode dialog.
3. Select a mode and adjust its labeled sidebar groups.
4. Click **Update Preview**, inspect the result, and click **Apply to Layer** or
   **Apply to Masters**. Preview preparation makes no font edits. The source image
   remains in place and application is undoable.

The older immediate Trace/Done controller remains in source for historical tests,
but these menu entries now use detached preview followed by explicit Apply.
The separately released build-15 payload is unchanged.

## Installation and compatibility

- macOS 13+, arm64 or x86_64; Glyphs 4.1 build 4107 or later within Glyphs 4.
- Glyphs Python 3.9+ with GlyphsApp, PyObjC, AppKit, Foundation and Quartz.
- Engine executable: `/Library/Application Support/beztrace/bin/beztrace`.
  Use **⋯ → Choose Engine…** for an explicit alternative; no ambient PATH lookup.
- Engine version must be exactly 0.1.0, 0.1.1 or 0.1.1-dev.1 through 0.1.1-dev.4 and match the returned JSON. PNG/JPEG source limits: 16 MiB,
  4096 × 4096 pixels. The normalized crop must also fit the input limits.

Install the bundle under the **actual Glyphs 4 Application Support directory**,
ending in `Plugins/Beztrace.glyphsPlugin`. Do not assume the Glyphs 3 directory.
The historical host inspection recorded a development link pointing to `.build/glyphs-companion-0.1.0-build11/Beztrace.glyphsPlugin` (build 11).
Replacing that payload requires a Glyphs relaunch to load its new code. Installed
files and the running revision are different evidence; About shows the loaded build.

The source package builder produces unsigned artifacts. Release signing and
native qualification are recorded separately in the release manifest. See [release procedure](RELEASE.md) for the
separate signing/notarization workflow. The plugin never saves a font.

For source development, `Plugins/Beztrace.glyphsPlugin` can be a symbolic link to
this checkout's `Companions/Glyphs/Beztrace.glyphsPlugin`. Preserve the previous
installation outside the Plugins folder first. Build the current development
engine with `python3 scripts/build_development_engine.py --output
.build/beztrace-0.2.1` from the repository root; the linked
plugin selects that executable automatically. Restart Glyphs after saving your
work, then open **Path → Beztrace Match Masters…**. Installation alone does not
change the running plugin. See [build 25 qualification](QUALIFICATION_BUILD25.md)
for current installed acceptance and [verification](VERIFICATION.md) for historical
builds and defects.

## Placement and safety

The native image's logical size, crop and full affine transform determine path
placement. The adapter normalizes the native image crop, requests neutral JSON,
then maps its complete canvas into image-local coordinates and applies the native
transform exactly once. It does not refit ink or consult font metrics in the UI.
Native bitmap rendering preserves image orientation and DPI-dependent logical size.
Crops outside the image and singular transforms are rejected with an actionable error.

Native writes use the qualified precision guard, balanced undo groups, recovery
snapshots and coordinate readback (1e-7 font units). Recovery is in-memory only;
it does not replace saved backups or provide application-crash recovery.

Auto-sizing is available only through the [placement API](AGENT_API.md). That API
places native images in explicitly specified layers; it never inserts paths.

## Build and verify

From the repository root, using Python 3.9+:

```sh
python3 -m unittest discover -s Companions/Glyphs/tests -v
python3 Companions/Glyphs/scripts/appkit_smoke.py
python3 scripts/verify_product_boundaries.py
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.2.0-build25-ready
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-0.2.0-build25-ready
```

The AppKit check requires macOS, PyObjC and WindowServer access; it uses fake font
objects. Engine integration tests trace all 100 immutable corpus images. Set
`BEZTRACE_TEST_ENGINE` if the released executable is not installed.
Packaging requires a fresh output directory and produces the bundle, deterministic
universal ZIP, manifest, SHA256SUMS, licenses, SDK provenance and SPDX SBOM.
It never signs, installs, or launches Glyphs.

The native CLI harness in [native testing](NATIVE_TESTING.md) uses detached,
disposable Glyphs font objects. See [build 25 qualification](QUALIFICATION_BUILD25.md)
for current native acceptance and remaining distribution checks.

[Installer integration](INTEGRATION.md) · [API evidence](SDK_EVIDENCE.md)

## Historical small-contour development fixes

Engine 0.1.1-dev.1 fixes the collapse of small closed contours reported with the
blob-letter image. Local 0.1.1-dev.2 also prevents unsafe final handle rounding
at valid Accuracy/Grid combinations. Local 0.1.1-dev.3 additionally prevents
Grid snapping from creating invalid topology. Local 0.1.1-dev.4 preserves
meaningful curvature on small convex contours. Engine 0.1.0 remains supported
but has those bugs; the shared installation is now stable 0.1.1. The commands
below describe the historical development workflow from its matching source
checkpoint. Use the published stable installer for current integration:

```sh
python3 scripts/build_development_engine.py
```

Historically the source companion selected
`.build/beztrace-0.1.1-dev.4/bin/beztrace`; build 25 now selects the matching
smoothing engine described above. **⋯ → Choose Engine…** remains available
for an explicit alternative in the trace panel; matching uses **Additional actions… → Choose
engine…**. A packaged companion outside the checkout still
defaults to the separately installed release. No system executable is replaced.
See [engine verification](../../docs/SMALL_CONTOUR_FIX.md).

## Stable engine 0.1.1 compatibility

Unsigned development build 12 adds exact engine 0.1.1 compatibility. Build 11
and earlier reject that version. This source update does not install or relaunch
the plugin, and the standalone 0.1.1 release does not distribute a companion.
Native UI qualification and companion publication remain separate.

Stable engine 0.1.1 is now separately published and verified. Build 12 has a verified unsigned local package; that historical installed build 11 rejects stable 0.1.1. Select the stable engine explicitly for the additional minimum-node cleanup; the preserved dev.4 artifact predates that follow-up. See the [integration handoff](../../docs/GLYPHS_MCP_V2_HANDOFF.md) for exact statuses and missing native work.

## Build 13: first-trace capture correction

Build 13 loads the native canvas image before recording its crop in the target
fingerprint. Glyphs initializes an unloaded image's default crop during that
read; capturing the earlier zero-sized crop caused the first trace to reject
its own image snapshot as an external edit. Explicit crops are preserved.
Actual content, crop, placement and source-file edits still invalidate results.
The standalone 0.1.1 engine, schema v1 and path-data v2 are unchanged.

This is a separately versioned unsigned development candidate. Automated
regressions do not establish complete native qualification or publication.

Build 13 also gives archive members a deterministic timestamp unique to the
companion build. This invalidates Glyphs' separate timestamp-based PythonCache
when updated source has the same size. Repeat packages of the same build remain
byte-identical; future changed distributions must increment the companion build.

For the historical build 13 review, environment-specific native results and pending
release gates, see [build 13 qualification](QUALIFICATION_BUILD13.md).


## Build 14 development prerelease

Build 14 preserves saved native preferences by normalizing PyObjC numeric
wrappers at the preferences boundary. Strict input validation remains intact.
It retains build 13's lazy image initialization and distinct build timestamp;
its ZIP timestamp is 2026-09-27 00:00:28. The stable engine 0.1.1 is unchanged.
See [build 14 qualification](QUALIFICATION_BUILD14.md). This unsigned companion
prerelease is independent of engine distribution and is not fully native-qualified.

## Build 15 signed release preparation

Build 15 corrects the About dialog to refer to the release manifest for signing
and qualification status. Its deterministic ZIP timestamp is 2026-09-27 00:00:30,
so it cannot reuse build 14 Python bytecode. The owner authorized independent
companion signing, notarization and official publication on 2026-10-05, then
explicitly waived native Intel testing because no recent Intel Mac is available.
Intel runtime qualification is untested and waived, never a passing result.
Universal loader slices remain present and signature-verified. Remaining native
gates must be reported from actual results; signing alone cannot qualify them.
See [build 15 qualification](QUALIFICATION_BUILD15.md).

## Persistent engine selection (0.2.1/build 26)

Both tracing and matching read
`~/Library/Application Support/beztrace/engine-settings-v1.json` on opening a
new panel. The v1 object contains `schemaVersion: 1` and optional absolute
`userEngine` and `managedEngine` paths. An explicit `userEngine` wins over
`managedEngine`, which wins over the source-checkout/system default. An invalid
or missing selected executable produces an error; it never silently selects
another engine. No ambient PATH search is performed.

**Choose Engine…** saves `userEngine` atomically while preserving managed and
unknown fields. Invalid, oversized or symlinked configuration is refused and
left unchanged. Selecting an engine never writes, installs, updates or replaces
an engine or companion installation. Existing panel jobs retain their selected
engine; reopen the panel after an external settings change.

The standalone engine and companion retain their macOS 13+ deployment targets.
Any narrower support policy in a separately distributed managed installer belongs
to that consumer; this release does not alter its catalog or installation rules.
