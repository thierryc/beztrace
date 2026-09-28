# Native qualification checklist

Status: **not performed**. Automated mock-host tests establish adapter logic,
not actual Glyphs undo semantics, plugin loading, or in-app rendering. The isolated AppKit smoke check is recorded separately.

Use an explicitly authorized disposable environment. Installation into live
Glyphs, relaunch, and editing user fonts are outside the current authorization.
Do not save dirty user fonts or close unrelated documents to make a test work.

## Bounded adapter probe

`scripts/native_probe.py` defines an opt-in `run(resources)` function for the
Glyphs Scripting Window. Pass the absolute path to the workspace plugin's
`Contents/Resources`. Importing the file has no font side effects. Calling it
creates a new unsaved fixture, inserts a closing cubic with fractional coordinates,
verifies readback and width, then leaves the disposable fixture open for Undo/Redo.
It does not exercise the plugin's menu or window and cannot qualify those features.

## Installed plugin acceptance

Record source revision, workspace and installed paths, bundle ID/version/build,
archive and payload hashes, app bundle ID/version/build, OS, CPU, Python version,
and evidence of the loaded revision. Preserve the previous installed bundle.

1. Install the exact staged bundle through the authorized Glyphs 4 installation
   workflow. Compare installed bytes. Relaunch only with authorization and verify
   **Path → Trace Image…** and the expected window.
2. Use a new disposable font with two glyphs, two masters, and a special layer.
   Add paths, a component, an anchor, guides, metadata, and widths including zero.
   Capture their initial values. Keep all tests within this fixture.
3. Trace corpus A/O and curved/counter fixtures; inspect source overlay, winding,
   smooth nodes, cubic closure, fractional handles, negative Bottom Y, and size.
   Include a JPEG with EXIF rotation/reflection and a transparent PNG.
4. Change placement without retracing; compare the preview's exact nodes to native
   readback. Verify existing content and advance width are preserved.
5. Exercise append and explicit replacement in both foreground and background.
   Confirm replacement preserves components/anchors and refuses hinted or locked
   paths. Verify background selection resolves the intended owning layer.
6. Undo once and compare the initial state; redo once and compare inserted paths.
   Repeat with font grid > 0 and both initial native rounding-flag states.
7. While tracing, navigate to another glyph/master/document. Apply must retain
   the captured target. Delete/replace/edit the target, close its document, or
   replace its background: Apply must refuse stale state. Use Current
   must explicitly capture the new selection.
8. Exercise malformed image, empty image, missing/wrong engine, invalid settings,
   repeated Trace, Cancel, window close during trace, timeout, and late worker
   completion. Confirm responsiveness and absence of orphan processes.
9. Use disposable fault injection to fail insertion/readback, then compare the
   recovered snapshot. Verify cleanup and poisoning on a recovery failure; never
   count a partial rollback as success.
10. Qualify install, update, rollback, and removal on both supported architectures.
    Verify no shared-engine removal and no unrelated plugin changes. Clean up only
    owned test bundles/fonts under the original authorization.

Record each case as passed, failed, blocked, or unverified with observed evidence.
A failure or unsupported selector remains a release blocker. Installed file hashes
alone do not prove which code Glyphs loaded.

## Build 2 inspector and overlay acceptance

- Check the 360 × 680 panel beside an edit view, 360 × 480 minimum, scrolling,
  fixed footer, collapsed/expanded settings, long errors and scrollable details.
  Check regular/larger text, long font/layer names, light/dark appearance,
  keyboard traversal, VoiceOver labels, and PNG/JPEG click/drop selection.
- Verify Auto for A/O, a/x and explicit `zero.lf` / `one.lnum`. J/Q, accents,
  descenders and unsuffixed numerals must need a choice. Check each explicit
  preset, missing/invalid/filtered layer metrics, and master fallback.
- Confirm Height/Bottom Y edits choose Custom, horizontal edits retain the preset,
  and placement edits update both previews without running the engine again.
- Compare exact overlay coordinates at several zoom levels and across masters,
  including negative descenders, fractional positions, counters, background mode,
  rotated/reflected JPEGs, and transparent PNGs. Guides must stay readable.
- Capture font change count, dirty state and undo state before previewing. Trace,
  resize, toggle source/outline, move the panel, and change placement; all font
  states must remain unchanged. Only Apply may create an undo group.
- Change metrics or glyph classification after tracing: the overlay must clear
  within the target-check interval and Apply must refuse until explicit refresh.
  Check callback removal on Cancel, settings changes, Apply, target removal, and
  panel close; reopening must never duplicate overlays.
- Compare thumbnail/overlay nodes to applied paths. Check native Undo/Redo,
  responsive navigation during tracing, duplicate Apply prevention, and recovery.
