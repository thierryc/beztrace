# Native qualification

See [verification](VERIFICATION.md) for observed results. Automated fake-host
checks, native CLI backend checks, and visible in-app qualification are separate.
Use disposable fixtures. Do not save, close, or edit unrelated user fonts.

## Reproducible native backend check

Using the official Glyphs CLI configured for Glyphs 4:

```sh
glyphs run --app '/Applications/Glyphs 4.app' --plugins '' \
  Companions/Glyphs/scripts/native_canvas_probe.py
```

This creates detached native font objects and synthetic raster fixtures under
`.build/glyphs-native-canvas`. It never connects to the running Glyphs document,
loads user plugins, installs, restarts, or saves a font. It verifies native image
and path insertion/readback, fractional affine transforms, crop/DPI/EXIF handling,
foreground/background preservation and native image/path Undo/Redo. Document
membership is replaced by an explicit detached-fixture ownership check; it cannot
establish in-app selection or menu behavior.

## Visible build-13 acceptance — pending

After an authorized relaunch, verify About shows build 13 and the menu reads
**Path → Beztrace…**. Use a new disposable font with two glyphs and two masters.

- Check the 300 × 210 collapsed, 300 × 410 expanded Auto-threshold and 300 × 434
  expanded Manual-threshold panel sizes. Confirm the top edge stays fixed, the
  Advanced Options disclosure sits at the far right, advanced labels are
  unindented, and keyboard order, accessibility labels, tooltips, long names,
  light/dark modes, readable errors and the engine setup action remain correct.
- Confirm first launch uses Auto threshold, Invert off, Balanced quality and a
  collapsed Advanced Options disclosure. Preset and Invert image must remain
  visible while Threshold is hidden. Exercise all presets and individual
  controls; invalid numeric text must show one inline system-red message, add
  enough panel height to avoid overlap, not retrace, and restore the last valid
  value when editing ends. Valid boundary values such as Smoothing 0.25 must not
  show an error. Close and reopen the panel to verify persistence, then use Reset
  Trace Settings and verify the defaults and collapsed state are restored.
- Place PNG/JPEG through Glyphs' normal image workflow. Confirm image Undo/Redo
  and move/resize with native handles. Exercise the separate placement API as needed.
- Check image/outline alignment at several zoom levels, including native crops,
  nonuniform scale, rotation, skew, reflection, 144-DPI PNG, EXIF JPEG and alpha PNG.
- Trace foreground and native background editing layers. Ensure counters and cubic
  handles match, existing outlines/components/anchors/width remain, and the source
  image is retained. Undo once and Redo once; compare exact path readback.
- Switch glyph/master/document during tracing: the result must stay on the
  captured target. Edit/replace/delete the image, crop, transform, file or target
  while tracing: reject the stale result without insertion.
- Exercise threshold errors, inversion, empty images, missing/wrong engine,
  Cancel, closure, timeouts, duplicate Trace and late results.
- Run the placement API on explicit disposable layers. Review proposed transforms,
  apply image-only placement, exercise Auto ambiguity and replacement conflicts,
  cancellation, whole-batch preflight failure and per-item recovery failure.

Record workspace, installed and loaded versions separately. No file checksum
alone establishes a loaded revision or visible alignment. A failed native check
remains a qualification blocker.

For build 13 and stable engine 0.1.1, set `BEZTRACE_TEST_ENGINE` to
`/Library/Application Support/beztrace/bin/beztrace` before an independently
authorized native run. Earlier dev.4 backend evidence is historical. Optional
`BEZTRACE_ACCEPTANCE_IMAGE` supplies a local PNG/JPEG for preparation, tracing,
affine insertion and Undo/Redo in the detached fixture. The harness writes a
normalized PNG and result JSON under `.build/glyphs-native-canvas` for comparison.
It never reads or edits a running user font. Omit the variable for public CI;
the user-supplied image is not a committed fixture.

### Build 13 first-trace regression

Attach a fresh PNG and a fresh JPEG without preloading their native image
properties. Verify each first Trace reaches Done in foreground/background,
including a default crop and an explicit crop. Confirm the source image,
existing paths/components/anchors and width survive. Verify native Undo and
Redo with the edit view focused; do not run mutation scripts between them.
Real image/crop/placement changes must still reject a pending result.

Current bounded results and remaining gates: [build 13 qualification](QUALIFICATION_BUILD13.md).


## Build 16 matching qualification

### Build 21 hint acceptance follow-up

On an explicitly authorized disposable font, confirm that hinted masters preview
in all paired modes. Apply a cyclic start/contour reorder and bounded subdivision;
verify every preserved hint's settings and all four node attachments against the
installed paths. Check absolute and ghost hints, unchanged reference identity,
and corner/cap adjacency. Removed nodes, retyped nodes, raster-derived destination
references and unsupported intersection attachments must refuse Apply before a
font write while keeping the preview and slider usable. Confirm that changing a
hint after preview invalidates the plan. Exercise Undo/Redo, save/reopen/export
and injected second-master failure with hints on both layers; verify paths,
hints, widths, images and precision state are restored. Isolated doubles do not
replace this installed-native acceptance.

### Original matching qualification

See [build 16](QUALIFICATION_BUILD16.md). For the detached probe:

```sh
BEZTRACE_MATCH_ENGINE=/absolute/beztrace/.build/beztrace-0.2.0-dev.1/bin/beztrace \
  glyphs run --app '/Applications/Glyphs 4.app' \
  --plugins '/Applications/Glyphs 4.app/Contents/PlugIns/HOI.glyphsTool' \
  Companions/Glyphs/scripts/native_matching_probe.py
```

This loads one built-in tool in an isolated CLI process and writes only synthetic
workspace fixtures. It does not install or relaunch the running app. After a
separately authorized installation/relaunch, qualify select → prepare → preview
→ apply → Undo/Redo → save/reopen → export, standalone file import, both placed
canvas-image modes, override selectors after ambiguity, cancellation and stale
inputs, unsupported layers/locks, Apply-only hint mapping refusals, and recovery failure blocking. Verify
compiled variable-font interpolation against native samples. Record loaded
build, exact payload hash, Glyphs/Python/OS, sources and all outstanding gates.

## Isolated AppKit matching panel (no font files)

Run from a macOS GUI session with WindowServer/application-registration access:

```sh
python3 Companions/Glyphs/scripts/appkit_smoke.py
python3 Companions/Glyphs/scripts/matching_appkit_smoke.py
```

The ordinary smoke uses disposable fake-host layers. The matching smoke uses a
write-blocking fake host and the actual workspace AppKit controller/renderer;
it never imports GlyphsApp, installs a plugin, opens a font, or saves/exports
font files. Build the development matching engine first, or set
`BEZTRACE_MATCH_ENGINE` to its executable. Optional `--hold 60` keeps only the
owned panel visible briefly for screen inspection; `--output PATH` selects the
local PNG/report directory (default `.build/glyphs-appkit-matching`). A successful
report appears only after all checks and window/timer cleanup; stale reports are
removed before a retry. View-cache PNGs verify custom drawing, while composited
native controls require actual screen inspection.

The parent runner preserves failures and reports native signals/timeouts. A
SIGABRT trace ending at `NSApplication` / `_RegisterApplication` can indicate a
restricted GUI environment; run the authorized isolated check with GUI access.
Do not skip it, classify the abort as a pass, or weaken the plugin. These checks
qualify isolated AppKit behavior only; loaded Glyphs, native font transactions,
save/reopen/export and architecture/release gates remain separate.


## Build 17 unified dialog acceptance

The isolated fake-host AppKit checks do not replace these installed-Glyphs checks:

- Verify both menu entries open the same four-mode dialog and select their intended
  starting mode. Inspect icon labels, keyboard focus, accessibility, light/dark
  appearance and inspector scrolling with Advanced open at common display scales.
- In Single image, review a detached trace before Apply to Layer; verify existing
  paths, image crop/transform, foreground/background destinations, Undo and recovery.
- Exercise image/image, outline/image and outline/outline matching. Confirm only
  relevant controls appear and all existing point/HOI gates still block invalid Apply.
- Update once: Update Preview becomes disabled and Apply receives the primary accent.
  Change a source, field, mode or engine: old preview remains, Update is secondary
  and enabled, Apply disabled, with no redundant stale notice. View/axis/disclosure
  changes and unchanged field events must not enable Update.
- Change the captured outline or image externally; Apply must be revoked. Cancel
  while processing and close while idle; late results cannot enable Apply or write.
- Confirm saved trace preferences survive a relaunch, and qualify native Apply,
  Undo/Redo, save/reopen and exported interpolation on disposable fonts.

Installation, relaunch and user-font testing require their separate authorization.


Build 18 retains the build-17 acceptance cases. Also verify native keyboard focus
and VoiceOver state/labels for all four stacked icon buttons, selecting the
already selected mode, mode changes while idle, dynamic accent/appearance,
Advanced-only utilities and long master names. Only the percentage is visible
under the slider; its tooltip retains the exact axis location. The simplified
footer must retain enabled Update/disabled Apply when regeneration is needed.
