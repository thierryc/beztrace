# Beztrace for Glyphs

A small native panel that traces the image already placed in Glyphs.
**0.1.0 build 14** accepts the separately installed **beztrace 0.1.0 or 0.1.1** engine
or local **0.1.1-dev.1** through **0.1.1-dev.4** development engines,
JSON schema **1**, and path data **2**.

## Use it

1. Open one glyph layer and choose **Path → Beztrace…**.
2. Place a PNG/JPEG using Glyphs' normal image workflow.
3. Move, resize, rotate, or crop the native image on the Glyphs canvas.
4. Choose a quality **Preset** and enable **Invert image** for light artwork on
   a dark background as needed. Open **Advanced Options** to change Threshold
   from **Auto** to **Manual** and use its slider or enter 0–255, or to adjust
   individual fitting controls.
5. Click **Trace**. Editable paths are appended at the image's canvas placement.
   The button becomes **Done**. Valid setting changes update these paths
   automatically; click **Done** to close the panel and keep the latest trace.
   Each successful update is undoable. The source image remains in place. If
   Grid would invalidate a contour, the engine retains that contour's safe
   no-grid geometry and reports the fallback in the panel.

The panel is 300 × 210 points by default and expands to 300 × 410 with Auto
Threshold while preserving its top edge. Preset and Invert image remain visible
when collapsed. The right-aligned Advanced Options disclosure reveals Threshold,
Accuracy, Smoothing, Corner sensitivity, Grid, Remove specks and Raster refinement
without nested label indentation. Manual Threshold adds 24 points for its slider
and numeric field. An invalid numeric value shows one inline system-red message,
temporarily adds 18 points so controls do not overlap, and suppresses retracing;
ending the edit restores the last valid value. Editing any advanced value selects
Custom unless it exactly matches a preset. Settings and the disclosure state
persist between panel sessions; **⋯ → Reset Trace Settings** restores Balanced,
Auto threshold, Invert off and the collapsed panel.

The panel has no sizing, preview, destination, or Apply controls.
It traces into the active foreground/background editing layer and preserves
existing outlines, components, anchors, and advance width, including zero width.
Image import remains available through the agent API. Normal native image selection
and transform controls remain in Glyphs. The built-in **Filter → Trace Image**
is a separate tool and is not changed by this plugin.

Tracing runs off the UI thread with progress and Cancel. A running trace stays
bound to the captured document and layer when you navigate. Changed destination
content, image files, crop, or placement invalidate the pending result. Setting changes debounce for 150 ms and cancel outdated results. Retracing
replaces only this session's output, preserving the original layer content.
External edits (including Undo), image changes, and changed targets stop live
replacement; finish the session and review the layer before tracing again. Errors appear in the panel, with
full details in **⋯ → Error Details…**. Recovery failures stop further writes.

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

Artifacts are unsigned local development builds. This is an informational status,
not a runtime tracing restriction. See [release procedure](RELEASE.md) for the
separate signing/notarization workflow. The plugin never saves a font.

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
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.1.0-build14
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-0.1.0-build14
```

The AppKit check requires macOS, PyObjC and WindowServer access; it uses fake font
objects. Engine integration tests trace all 100 immutable corpus images. Set
`BEZTRACE_TEST_ENGINE` if the released executable is not installed.
Packaging requires a fresh output directory and produces the bundle, deterministic
universal ZIP, manifest, SHA256SUMS, licenses, SDK provenance and SPDX SBOM.
It never signs, installs, or launches Glyphs.

The native CLI harness in [native testing](NATIVE_TESTING.md) uses detached,
disposable Glyphs font objects. See [verification](VERIFICATION.md) for passed
checks versus remaining visible in-app qualification.

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

When the development companion runs from this source checkout and
`.build/beztrace-0.1.1-dev.4/bin/beztrace` is executable, the panel selects that
corrected development engine automatically. **⋯ → Choose Engine…** remains
available for an explicit alternative. A packaged companion outside the checkout
still defaults to the separately installed release. No system executable is
replaced. See [engine verification](../../docs/SMALL_CONTOUR_FIX.md).

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
