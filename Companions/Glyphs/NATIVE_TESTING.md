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

## Visible build-12 acceptance — pending

After an authorized relaunch, verify About shows build 12 and the menu reads
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

For build 12 and stable engine 0.1.1, set `BEZTRACE_TEST_ENGINE` to
`/Library/Application Support/beztrace/bin/beztrace` before an independently
authorized native run. Earlier dev.4 backend evidence is historical. Optional
`BEZTRACE_ACCEPTANCE_IMAGE` supplies a local PNG/JPEG for preparation, tracing,
affine insertion and Undo/Redo in the detached fixture. The harness writes a
normalized PNG and result JSON under `.build/glyphs-native-canvas` for comparison.
It never reads or edits a running user font. Omit the variable for public CI;
the user-supplied image is not a committed fixture.
