# Verification record — companion 0.1.0

Date: 2026-09-27. Branch: `lit/glyphs-companion`.
Git base: `b78f601e54a3486de914753a0bd7e6fd67e1b5cb`.
Host: arm64, macOS 26.7.1 (25G309), Python 3.14.6.
Installed engine SHA-256:
`754220d418ef4d2e5e3af8b762e6cb96537e0e6e7be1d4f2e96a9ce470e7d4eb`.
The optimized Swift suite completed in 153.489 seconds; the build-2 68-method companion
suite completed in 36.269 seconds. The Swift run belongs to build-1 validation;
Swift sources are unchanged in build 2.

## Automated evidence

| Check | Result |
| --- | --- |
| Pure contract, geometry, placement, process, state, recovery, and packaging suite | Passed: 68 test methods, including the full 100-image real-engine corpus |
| Released engine integration | Passed using installed `beztrace 0.1.0`; every frozen image returned valid neutral schema-v1/pathDataVersion-2 JSON |
| Existing optimized Swift suite (prior build-1 run, unchanged engine) | Passed: 84 tests, one intentional maintenance-export skip, zero failures |
| SDK scaffold validator | Passed: identity, principal class, syntax, pinned loader hash, attribution, and placeholders; `runtimeTested: false` |
| Universal loader | Verified `arm64` and `x86_64` slices |
| Reproducible unsigned packaging | Passed: two separate builds yielded identical manifests and ZIP bytes |
| Manifest, archive, unpacked payload and checksum validation | Passed; tampered archive and payload rejection covered |
| Isolated AppKit smoke check | Passed with real AppKit/PyObjC and a fake host: panel/control construction, image loading, cached drawing, placement editing, layout bounds, invalidation, stale worker results, and callback/timer cleanup |
| Standalone product-boundary audit | Passed; no core, CLI, Swift package, or public tracing schema changes |
| Whitespace/diff check | Passed |

Process tests cover both full stderr before stdin consumption and large stdout,
termination escalation, timeouts, cancellation, invalid versions, every documented
CLI exit code, invalid successful output, and late-generation results. Geometry
checks include cubic closure across the start index, rotated starts, exact cubic
bounds and area, opposed counter winding, and uniformly transformed handles.
Adapter tests use fake host objects; construction/readback tests use native-class
test doubles. They do not exercise Glyphs' actual object implementation.

The initial Swift invocation was blocked by the sandbox's compiler-cache access.
The authorized retry with cache access completed successfully; no failing Swift
regression was hidden or skipped.

The build manifest records the Git base revision and `sourceTreeDirty: true` for
this uncommitted implementation. Its full payload inventory identifies the built
bytes. Packaging outputs are under `.build/glyphs-companion-0.1.0-build2`; test logs are local
build evidence, not immutable corpus fixtures.

## Build 2 coverage

The 22 added test methods cover supported and ambiguous Auto cases, lining-figure
fallback, all presets, filtered layer metrics, master fallback, invalid/conflicting
metrics, manual overrides, stale metric/classification capture, shared cubic
geometry, counter winding, guides, callback lifetime, action states and stale
worker completion. Existing contract/process/recovery/packaging tests remain.

`scripts/appkit_smoke.py` exercises the actual AppKit/PyObjC controls and renderer
in a separate process with a fake host. It checks thumbnail modes, overlay drawing
at 0.25×/1×/4×, both appearance API paths, larger text, expanded controls/details,
three panel sizes, and cleanup. It verifies no mock-layer mutations or undo groups.
It does not establish visual quality, VoiceOver behavior, Glyphs integration,
image alignment within the edit view, or actual font change/undo behavior.

WindowServer access was unavailable in the filesystem sandbox (NSApplication
terminated before construction). The bounded isolated check passed with that
access. An offscreen view-cache image did not reliably capture native controls;
it is not visual qualification evidence. No Glyphs process or font was accessed.

## Build 2 status before installation

**Unverified:** native menu/window loading, layout, image orientation/overlay,
background-owner resolution, precision selector behavior on this revision,
foreground/background insertion, native undo/redo, and native rollback.

Glyphs MCP's read-only planning status identified Glyphs 4.1 build 4107. It did
not establish that this plugin was installed or loaded. No user font was read,
changed, or saved. No live installation or Glyphs restart was performed.

`scripts/native_probe.py` and `NATIVE_TESTING.md` provide the disposable native
probe and full checklist. Run them only in an authorized test environment and
record exact installed/loaded revisions. Failed or unverified cases remain
release blockers.

**Not performed:** Developer ID signing, Apple notarization, signed package
verification, installation/update/removal qualification, tagging, and publication.
The built ZIP and manifest are explicitly unsigned and native-unqualified.

## Preserved work

The pre-existing untracked `Tests/Fixtures/corpus/deterministic/traced-review/`
export was subsequently audited during repository cleanup: all 24 JSON results
match released engine output and the HTML contains no acceptance decisions. Its
74 files were archived losslessly with SHA-256 verification under the ignored
`.local-archives/traced-review-2026-09-27.zip` before removal from the fixture tree.
The archive inventory records every original path and hash. Engine source, CLI source, package definition, and
public JSON schema remain unchanged. No Glyphs MCP repository files were edited.

## Build 3 — native target-capture correction (2026-09-28)

The user authorized development-link installation. Build 2 was installed under
Glyphs 4's Plugins directory with its link pointing to
`.build/glyphs-companion-dev/Beztrace.glyphsPlugin`. The user's subsequent
screenshot shows the Beztrace panel and About version 0.1.0/build 2: this is
user-supplied evidence that the development plugin loaded. It also shows target
capture failing with `'NoneType' object is not iterable`. The About dialog's
unsigned notice is informational, not a signing rejection.

The SDK's optional collection proxies reproduce that exception when native
storage is nil. Before the correction, five of six new regression cases fail;
after it, all six pass. They cover empty target capture, actual None versus an
empty collection, later annotation changes, replacement with/without hints,
missing metric stores, and propagation of unexpected read failures. Build 3
normalizes only nil collections, preserving stale-target and recovery checks.
Native exception details now include a traceback; About clarifies its notice.

The complete companion suite passes 74 methods, including the 100-image released
engine corpus and deterministic package checks. SDK scaffold validation,
standalone-boundary audit, diff checks, and the isolated AppKit smoke check pass.
The Swift core, CLI and tracing schema are unchanged.

The rebuilt development payload is build 3; its previous build-2 payload is
retained locally before replacement. Workspace/build/link identity and payload
checksums are verified in `.local-archives/beztrace-development-install.json`.
The linked directory must be rebuilt after future source changes; source edits
alone do not update the installed payload. No signing or Glyphs restart is
performed by this correction. No font is modified. Build-3 loading, successful
capture in the user's font, application, and Undo/Redo remain unverified until
the user relaunches Glyphs and native checks are authorized.

## Build 4 — defer target capture beyond the button action (2026-09-28)

Build 3 was observed loaded through its exception traceback. Read-only MCP
context reported one selected layer while Use Current failed. A temporary,
one-call diagnostic in the native scripting window established that both
`font.selectedLayers` and `font.currentTab.selectedLayers` were empty *during*
the button action. They were populated outside the action, including while the
Beztrace inspector remained key. Deferring the full existing capture routine by
0.1 seconds on the main thread passed: glyph `fl`, layer `Thin Condensed`, with
baseline 0, cap height 1400, x-height 1000, ascender 1984, descender -494.
No glyph outlines, metrics, font files, or saved state were changed by the probe.
Temporary diagnostic wrappers were removed afterward.

Build 4 queues explicit capture on the inspector timer and rejects a changed,
closed, or replaced document/font/tab. Empty or multiple selections still fail.
Image loading, tracing option changes, and engine selection retain target error
details instead of saying to Trace while Trace is disabled. Successful explicit
refresh clears the error. Panel closure cancels pending capture.

Automated validation: 77 companion tests passed, including released-engine corpus
and deterministic package checks. The isolated AppKit smoke check additionally
covers selection unavailable during the action but available afterward, an actual
empty selection, error persistence after image loading, document switching,
explicit refresh, button state, and closure before deferred capture.
The scaffold and standalone-boundary checks also pass.

The linked development payload is rebuilt as 0.1.0/build 4, with build 3 retained
locally for rollback. See `.local-archives/beztrace-development-install.json` for
payload and loaded-revision evidence. No relaunch, signing, or publication was
performed. The native read-only timing probe passed; the complete build-4 panel
has not yet been loaded in Glyphs. Insertion, preview alignment and Undo/Redo
qualification remain pending and are not established by this diagnostic.

## Build 5 — native canvas tracing and placement-only API (2026-09-28)

The user authorized replacing the inspector and rebuilding the existing
installation link. The menu is now **Path → Beztrace…**, distinct from Glyphs'
Filter → Trace Image. The native panel is 280 × 190 points with Choose Image,
Auto/manual Threshold, Invert and Trace/Cancel. Trace inserts directly into the
captured active editing layer. Image placement belongs to native Glyphs controls;
no metric fitting or custom preview callbacks are used by the panel.

The Python API v1 prepares a cancellable image-placement plan off the UI thread
and applies it explicitly on the main thread. Clients poll `Preparation.done`;
completion never schedules a font mutation. All targets are preflighted before
application, and partial results identify completed, failed and unattempted items.

### Automated checks

- 94 companion tests: geometry, counters/reflections/cubic handles, padding/crop,
  uniform API sizing, invalid images/output, process cancellation/timeouts,
  stale targets/sources, batch conflicts/cancellation/failure/recovery and packaging.
  The released-engine integration covers all 100 immutable corpus fixtures.
- Isolated AppKit smoke: compact controls, native raster preparation with the
  real engine, deferred capture, automatic insertion through a fake host,
  duplicate prevention, changed document, invalid threshold, cancellation and closure.
- SDK scaffold validation, standalone dependency boundary and whitespace checks.
- Deterministic unsigned ZIP, manifest/inventory and archive checksums.

### Native backend checks completed

Official Glyphs CLI, Glyphs **4.1 build 4107**, Python **3.14**, user plugins
disabled, detached disposable GSFont objects only. No running user font was read,
modified, saved or closed. The harness generated scratch raster fixtures under
`.build/glyphs-native-canvas` and used the released 0.1.0 engine.

Passed: nine translated/rotated/reflected/skewed/nonuniform transform cases,
fractional crop, 144-DPI PNG, EXIF-6 JPEG, counters, exact node readback within
1e-7 units, source-image/zero-width preservation, background insertion, and native
image/path Undo/Redo. The placement API's asynchronous preparation leaves the
fixture unchanged; image-only application fits ink to X=40 and Y=-120…580 and
supports native Undo/Redo. Raster ink bounds are checked within 1.5 source pixels
for the synthetic rectangle; exact insertion compares against computed geometry.

The first harness attempt allowed Undo to consume its setup width change. The
corrected harness finishes setup groups and clears only the detached fixture's
undo history before testing. Failed attempts were not counted as passes. A
callback experiment did not dispatch under the CLI run loop; the final API uses
nonblocking completion polling and explicit main-thread application instead.

### Installation and remaining qualification

Build 5 is rebuilt into the existing development-link payload with the previous
build 4 retained for rollback. The local installation record captures hashes and
source revision/dirty state. The shared engine and built-in Glyphs filter are
unchanged. No signing, notarization, publication or Glyphs relaunch was performed.

Visible in-app menu/window behavior, native image-handle interaction, live
foreground/background selection, screen alignment at different zoom levels and
full installed-plugin Undo/Redo remain pending an authorized relaunch and
in-app disposable-font check. The manifest remains `development-unqualified`
with no fully qualified native builds; backend checks are not promoted to full
plugin qualification. See NATIVE_TESTING.md for the bounded acceptance steps.

## Build 6 — small-contour engine compatibility (2026-09-28)

Build 6 supports exact engines 0.1.0 and 0.1.1-dev.1. It compares the returned
JSON version with the executable's version probe; unsupported and mismatched
versions fail before native insertion. The UI and JSON contract remain unchanged.

The full 95-test companion suite passed with the corrected engine. Native CLI
checks on disposable Glyphs 4.1/4107 objects include the supplied blob image:
48 contours, native 144-DPI image size 503 × 485, transformed coordinate readback,
source/width preservation and Undo/Redo. The isolated AppKit panel smoke also
passed. See [engine evidence](../../docs/SMALL_CONTOUR_FIX.md) for the Swift
regressions, unchanged 100-image corpus and raster comparison limitations.

Build 6 replaces the existing development-link payload with build 5 retained for
rollback. The local universal development engine is separate from the bundle;
select it explicitly with Choose Engine after relaunch. The shared 0.1.0 engine
is untouched. Installed files are verified; loaded build 6 remains unverified.
No Glyphs relaunch, user-font edit, Developer ID signing or publication occurred.
The manifest remains development-unqualified pending full visible in-app tests.
