# Beztrace for Glyphs

A small native panel that traces the image already placed in Glyphs.
**0.1.0 build 6** accepts the separately installed **beztrace 0.1.0** engine
or the local **0.1.1-dev.1** development engine,
JSON schema **1**, and path data **2**.

## Use it

1. Open one glyph layer and choose **Path → Beztrace…**.
2. Click **Choose Image…**, or place a PNG/JPEG using Glyphs' normal image workflow.
3. Move, resize, rotate, or crop the native image on the Glyphs canvas.
4. Leave Threshold on **Auto**, or choose **Manual** and enter 0–255. Enable
   **Invert** for light artwork on a dark background.
5. Click **Trace**. Editable paths are appended at the image's canvas placement.
   One native Undo reverses the insertion. The source image remains in place.

The 280 × 190 point panel has no sizing, preview, destination, or Apply controls.
It traces into the active foreground/background editing layer and preserves
existing outlines, components, anchors, and advance width, including zero width.
Choosing a new image requires confirmation before replacing an existing image;
image placement is a separate undoable operation. Normal native image selection
and transform controls remain in Glyphs. The built-in **Filter → Trace Image**
is a separate tool and is not changed by this plugin.

Tracing runs off the UI thread with progress and Cancel. A running trace stays
bound to the captured document and layer when you navigate. Changed destination
content, image files, crop, or placement invalidate the pending result. Repeating
an unchanged completed operation is rejected. Errors appear in the panel, with
full details in **⋯ → Error Details…**. Recovery failures stop further writes.

## Installation and compatibility

- macOS 13+, arm64 or x86_64; Glyphs 4.1 build 4107 or later within Glyphs 4.
- Glyphs Python 3.9+ with GlyphsApp, PyObjC, AppKit, Foundation and Quartz.
- Engine executable: `/Library/Application Support/beztrace/bin/beztrace`.
  Use **⋯ → Choose Engine…** for an explicit alternative; no ambient PATH lookup.
- Engine version must be exactly 0.1.0 or 0.1.1-dev.1 and match the returned JSON. PNG/JPEG source limits: 16 MiB,
  4096 × 4096 pixels. The normalized crop must also fit the input limits.

Install the bundle under the **actual Glyphs 4 Application Support directory**,
ending in `Plugins/Beztrace.glyphsPlugin`. Do not assume the Glyphs 3 directory.
The current development link points to `.build/glyphs-companion-dev/Beztrace.glyphsPlugin`.
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
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.1.0-build6
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-0.1.0-build6
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

## Small-contour development fix

Engine 0.1.1-dev.1 fixes the collapse of small closed contours reported with the
blob-letter image. Released 0.1.0 remains installed and supported, but still has
that bug. Build the local universal engine from the repository root:

```sh
python3 scripts/build_development_engine.py
```

After loading companion build 6 with a Glyphs relaunch, choose **⋯ → Choose Engine…**
and select `.build/beztrace-0.1.1-dev.1/bin/beztrace` inside this repository. The
choice applies to this panel session; select it again after reopening the panel.
The default remains the separately installed release. No system executable is
replaced. See [engine verification](../../docs/SMALL_CONTOUR_FIX.md).
