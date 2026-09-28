# Beztrace for Glyphs

A native Glyphs 4 companion that traces PNG/JPEG images into editable paths
using the separately installed beztrace engine. Plugin version **0.1.0**, build
**2**, requires **beztrace 0.1.0**, JSON schema **1**, path data **2**.

**Development artifact: native UI, insertion, Undo/Redo, installation, and
signed distribution are not yet qualified.** See [verification](VERIFICATION.md).

## Requirements and layout

- macOS 13+, Apple Silicon or Intel; universal SDK loader.
- Glyphs 4.1 build 4107 or later within Glyphs 4, with its Python 3.9+ runtime
  and GlyphsApp, PyObjC, AppKit, Foundation, and Quartz bindings.
- The released engine at `/Library/Application Support/beztrace/bin/beztrace`,
  or a user-selected absolute executable through **⋯ → Choose Engine…**.
- Install the bundle as `Plugins/Beztrace.glyphsPlugin` relative to the
  **actual Glyphs 4 Application Support directory**. Discover that directory
  using Glyphs 4's own settings/API; do not assume a Glyphs 3 directory.
- Glyphs loads plugins on launch. Copying files does not load a new revision.

The companion does not download an engine or require Glyphs MCP to operate.
The repository's Swift package and standalone distributions remain independent.

## Workflow

Select exactly one stored glyph layer, then choose **Path → Trace Image…**.
Choose an image, adjust settings, trace, review, and Apply. The destination is
captured by object identity and stable glyph/layer IDs. The window names the
captured target; navigating elsewhere never redirects it. **Use Current**
explicitly binds a new target and clears the previous trace.

Foreground/background can be chosen for that captured owner. Append preserves
existing shapes. **Replace existing paths** displays the path count and asks for
confirmation when applying; components and anchors remain. Replacement refuses
locked paths and layers with hints, because hints may reference removed nodes.

The nonmodal 360 × 680-point inspector floats beside the edit view while Glyphs
is active. Its content scrolls; Trace/Apply and status remain visible. Click the
thumbnail, use **Change…**, or drop one PNG/JPEG onto it. **Image / Overlay /
Outline** switches the thumbnail view. Advanced tracing controls start collapsed.
The overflow menu holds engine selection, version information, and a larger-text
option. Native controls use system typography, colors, and light/dark appearance.

### Fit to font metrics

Placement defaults to **Auto**. Applicable layer metrics take precedence over the
associated master's metrics. Conflicting or invalid metrics require an explicit
usable preset or Custom values.

| Fit to | Complete ink range |
| --- | --- |
| Cap height | Baseline → cap height |
| x-height | Baseline → x-height |
| Ascender | Baseline → ascender |
| Descender | Descender → x-height |
| Custom | Bottom Y → Bottom Y + Height |

Auto supports plain Unicode Latin uppercase A–Z except J/Q, lowercase
`a c e m n o r s u v w x z`, and digit names explicitly ending in `.lf` or
`.lnum`. Lining figures use cap height as a labeled fallback. Other glyphs,
including accented letters, descending capitals, alternates, and unmarked
numerals, require a preset or Custom. Unresolved Auto disables Apply.

The inspector shows the resolved rule and numeric range. Editing Height or
Bottom Y chooses Custom; horizontal adjustment preserves the preset. Custom
starts at height 700 and Bottom Y 0 before any metric resolution; subsequent
manual edits retain the displayed values. Horizontal position defaults to 0
and denotes the final left ink edge. One positive uniform transform fits the
complete ink bounds, including handles. Advance width is preserved, including
zero width. No AI, image classification, optical overshoot, or accent separation
is used. There is no additional grid snapping.

### Live preview

**Preview in Glyphs** is enabled by default. The captured layer is the preview
canvas; navigating elsewhere never retargets it. The optional source overlay is
off by default. Labeled baseline, x-height, cap-height, ascender, and descender
guides accompany the system-accent outlines. The thumbnail and overlay use the
same transformed node data as Apply, with a compound nonzero fill for counters.
ImageIO normalizes raster orientation.

Placement edits update both previews immediately. Tracing-setting edits clear
the old outlines and require Retrace. Drawing callbacks use cached paths and
perform no tracing, file access, or font mutation. Cancellation, invalidation,
Apply, target removal, and window closure clear the preview and remove callbacks.
Target state is checked outside drawing every half second and immediately before
Apply. Preview never intentionally changes font content or creates an undo group;
actual Glyphs behavior remains subject to native qualification.

Trace runs in a worker thread with bounded subprocess pipes. Version checks
expire after five seconds; tracing after 60. Cancel stops and reaps the child.
The spinner describes stages, not a fabricated completion percentage.
Inputs are limited to 16 MiB and 4096 × 4096 pixels. Outputs are limited to
32 MiB and 100,000 nodes total; the released schema limits each contour to 4,096.

## Safety and recovery

Apply rechecks document membership, ownership, glyph lock, native precision
support, glyph classification, captured metrics, and destination content. Changed
metrics or destination content require a new capture and trace. Native writes run on the main thread in a balanced undo group.
Detached native paths retain closure, node order, smooth flags, and winding.
Coordinates are read back with an absolute tolerance of 1e-7 font units.

Recovery copies are captured immediately before writing. Failure restores the
previous shapes and width and verifies the complete captured state. A recovery
or cleanup mismatch blocks further Apply in that window and reports possible
partial edits. Successful insertion can be undone/redone in Glyphs. These are
in-memory recovery measures; they do not protect against application crashes or
replace the user's saved font backups. The plugin never saves the font.

## Build and test

From the repository root, using Python 3.9+:

```sh
python3 -m unittest discover -s Companions/Glyphs/tests -v
swift test --configuration release --disable-swift-testing
python3 scripts/verify_product_boundaries.py
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.1.0-build2
```

The package destination must be new or empty; existing artifacts are preserved.
Tests require a real engine. Set `BEZTRACE_TEST_ENGINE` to a built or extracted
0.1.0 executable when the released engine is not installed. Integration tests
trace all 100 immutable corpus images without rewriting fixtures.

Packaging checks the pinned SDK loader hash, universal architectures, Python
syntax, identity, and schema copy. It creates the bundle, deterministic unsigned
ZIP, companion manifest, SHA256SUMS, and SPDX SBOM. Build artifacts are not
committed. Packaging never signs, installs, or launches Glyphs.

[Integration guide](INTEGRATION.md) · [Release procedure](RELEASE.md) ·
[Native qualification](NATIVE_TESTING.md) · [SDK evidence](SDK_EVIDENCE.md)

An optional isolated AppKit check uses only a fake host and corpus images:

```sh
python3 Companions/Glyphs/scripts/appkit_smoke.py
```

It requires PyObjC with AppKit/Quartz and WindowServer access. It verifies native
control construction and drawing API calls, without installing the plugin,
connecting to Glyphs, or accessing a font. It is not visual/native qualification.
