# Companion verification history

Current release: **0.2.0/build 25**, using engine **0.2.1** for matching. Both
signed universal distributions are Apple-notarized and published. Signed native
UI Apply/Undo/Redo and install/update/rollback/removal/reinstallation pass on
Apple Silicon / Glyphs 4.2/build 4202. Native Intel remains untested and explicitly
owner-waived for these versions. See [build 25 qualification](QUALIFICATION_BUILD25.md)
and the [final release record](../../docs/RELEASE_0.2.1.md).

The entries below retain the results and pending statuses recorded at each
historical checkpoint; they do not describe the current release status.

## Initial verification — companion 0.1.0

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

## Interactive trace source update

The panel now uses Trace → Done, manual threshold slider/text synchronization,
150 ms setting debounce and generation cancellation. Successful updates replace
this session's paths through the original-content snapshot, with each update
undoable. Original content and the last successful trace are preserved on failed
replacement. External edits invalidate replacement. Choose Image is removed;
the image-placement API remains. Agent preparation/application now also exposes
canvas tracing and every engine trace option, including diagnostics.

The companion suite and isolated AppKit check cover replacement, failed-apply
recovery, stale targets/results, numeric validation, Done closure, agent options,
cancellation and single application. AppKit uses fake font objects with the real
engine. Live Glyphs slider interaction and native Undo/Redo for repeated updates
still require visible qualification; these source changes were not installed.

## Build 8 — expandable trace quality controls (2026-09-28)

Build 8 adds a pure settings model and an Advanced disclosure to the native
trace panel. The collapsed panel is 320 × 210 points; the expanded panel is
320 × 408 and preserves its top edge. Balanced, Sharp and Smooth Detail
presets map to the existing engine options without changing Threshold or Invert.
Individual edits select Custom, valid changes share the 150 ms live-retrace
debounce, and invalid text restores the last valid value when editing ends.
The versioned defaults dictionary retains valid settings and disclosure state;
invalid or obsolete data falls back to Balanced and collapsed. Reset Trace
Settings also restores Auto threshold and Invert off.

Automated validation completed on the source checkout:

- 104 companion tests passed, including the 100-image engine corpus, preset and
  Custom detection, numeric boundaries, persistence fallback, existing
  cancellation/stale-target/live-replacement/undo behavior, engine selection and
  deterministic package checks.
- The isolated AppKit smoke check passed with fake font objects and the real
  engine. It covered both dimensions, stable top edge, keyboard routing,
  accessibility labels, slider/text synchronization, one retrace per preset,
  reset, restoration across controller instances and Aqua/Dark Aqua construction.
- The optimized Swift suite passed 89 tests with one intentional
  maintenance-export skip and zero failures.
- The standalone product-boundary audit and whitespace check passed.
- The unsigned build-8 package was created and verified at
  `.build/glyphs-companion-0.1.0-build8`; its manifest and `SHA256SUMS` record
  the final archive and payload hashes.

The package remains `development-unqualified`, unsigned and not notarized. It
was not installed, Glyphs was not relaunched, and no user font was accessed or
modified. Visible in-app layout, VoiceOver behavior and repeated-update Undo/Redo
remain subject to the separately authorized native acceptance procedure.

## Build 9 — handle-rounding and smoothing-endpoint repair (2026-09-29)

Build 9 accepts engines 0.1.0, 0.1.1-dev.1 and 0.1.1-dev.2, preferring the
new local 0.1.1-dev.2 engine from a source checkout. The engine now shares its
handle-reach and handle-triangle safety calculation between final cleanup and
geometry validation. Integer handle rounding is retained only when the rounded
curve remains valid; otherwise cleanup preserves the safe pre-rounded handles.
Validation limits, public APIs and JSON schemas are unchanged.

Automated validation completed on the source checkout:

- The optimized Swift suite passed 91 tests with one intentional
  maintenance-export skip and zero failures. Focused coverage proves unsafe
  rounded handles fall back while safe rounding remains deterministic, and
  `symbol-sparkle.png` validates at Accuracy 3, Smoothing 0.7 and Grid 1.
- All 100 immutable corpus fixtures traced successfully at defaults with the
  fresh universal 0.1.1-dev.2 engine.
- The private blob reproduction remained outside tracked fixtures and traced
  successfully at Accuracy 0.5, 0.75, 1, 1.5, 2, 2.5, 2.75 and 3 with
  Smoothing 0.7 and Grid 1.
- All 105 companion tests passed, including cancellation, stale-target
  protection, live replacement, Undo/application paths, presets, persistence,
  engine selection and deterministic packaging.
- The isolated AppKit smoke check passed both panel sizes, the exact 0.25
  Smoothing slider endpoint, field synchronization, one debounced retrace and
  the existing native-raster/fake-host lifecycle without accessing Glyphs or a
  user font.
- The standalone product-boundary audit, four release-metadata tests and
  whitespace check passed.

The unsigned universal engine is stored separately at
`.build/beztrace-0.1.1-dev.2/bin/beztrace` with SHA-256
`38ceb3c266cc37ddbbc3269554a2b2b6e808e933c593d544133787111661fad3`.
Build 8 and engine 0.1.1-dev.1 remain available for rollback. The build-9
package stays `development-unqualified`; it is not signed, notarized or
published, and the released shared 0.1.0 engine is not replaced.

## Build 10 — topology-safe Grid cleanup (2026-09-29)

Build 10 accepts engines 0.1.0, 0.1.1-dev.1, 0.1.1-dev.2 and 0.1.1-dev.3,
preferring the fresh local dev.3 engine from a source checkout. Grid candidates
are now accepted only when the shared final validator accepts the complete
outline. A rejected candidate retains that contour's fully cleaned no-grid
geometry and adds a deterministic warning. Invalid no-grid geometry still
fails closed. Remove Specks, all control ranges, schema v1 and public Swift
request/result types are unchanged.

The native panel is redesigned at 300 × 210 points collapsed and 300 × 410
expanded with Auto Threshold. Preset and Invert image remain visible, while
Threshold leads the unindented controls under a separate Advanced Options label
and far-right native disclosure button. Manual Threshold adds 24 points for its
second-line controls. Invalid numeric input uses an associated inline system-red
message, adds 18 points without moving the top edge, suppresses retracing, and
restores the last valid value when editing ends. The footer remains reserved for
progress and global engine or destination errors.

Automated validation completed on the source checkout:

- The optimized Swift suite passed 97 tests with one intentional
  maintenance-export skip and zero failures. This includes all 100 default
  corpus traces and 200 additional boundary-profile traces at Grid 8.
- Pure cleanup tests cover collapsed anchors, self-intersections, safe
  candidates, deterministic mixed fallback and invalid fallback failure.
- Committed regressions for `glyph-upper-n.png`, `symbol-gear.png` and
  `symbol-crescent-moon.png` pass at Accuracy 0.5, Smoothing 2.5, Corner 13,
  Grid 8 and Remove Specks 700, each with the expected warning.
- The untracked private blob passed 216 combinations spanning boundary
  Accuracy, Smoothing, Corner, Grid, Remove Specks and refinement values with
  zero failures.
- All 107 companion tests passed, including warning validation/display,
  cancellation, stale-target protection, live replacement, Undo/application
  paths, presets, persistence, engine selection and deterministic packaging.
- The isolated AppKit smoke check passed with the universal dev.3 engine and
  verified the 300-point layout, fixed top edge, right disclosure, unindented
  controls, Manual Threshold synchronization, inline validation, keyboard and
  accessibility order, persistence, Aqua/Dark Aqua construction and warning
  status without accessing Glyphs or a user font.
- The product-boundary audit, four release-metadata tests and whitespace check
  passed.
- A 50-image optimized default batch took 15.53 seconds on dev.2 and 15.47
  seconds on dev.3 on the same machine and checkout.

The unsigned universal engine is stored at
`.build/beztrace-0.1.1-dev.3/bin/beztrace` with SHA-256
`ec96e34ae9c4b29a044e2d00719b9c6c5844da84d5540f5db7d6d3085228e865`.
The redesigned unsigned companion package is stored at
`.build/glyphs-companion-0.1.0-build10`; its deterministic archive
`beztrace-glyphs-0.1.0-build10-macos-universal.zip` has SHA-256
`d07327367999748595a1977b2a2819e12130361bd784650e2449cd12ed539700`.
Read-only verification passed for its manifest, archive, payload and checksums;
native qualification remains `development-unqualified`.
Earlier development engines and companion builds remain available for rollback.
Dev.3/build 10 are not signed, notarized or published, and the released shared
0.1.0 engine is not replaced.

## Build 11 — protected small convex curves (2026-09-29)

Build 11 accepts engines 0.1.0 and 0.1.1-dev.1 through 0.1.1-dev.4, preferring
the fresh local dev.4 engine from a source checkout. Dev.4 detects suspicious
line substitutions only on small, coherently turning convex contours, refits
those contours with the existing closed cubic fitter, and excludes only their
straightening cleanup. Raster refinement, the remaining cleanup passes and
final geometry validation remain enabled. Public options, schema v1 and path
data version 2 are unchanged.

Automated validation completed on the source checkout:

- The optimized Swift suite passed 99 tests on both arm64 and x86_64/Rosetta,
  with one intentional maintenance-export skip and zero failures.
- Synthetic circles and rotated or elongated ovals stay closed, valid,
  deterministic and curve-only across the supported presets and threshold
  coverage. Rectangles, triangles, rounded rectangles, pills with flats,
  concave outlines and large contours retain their intended structure.
- The 100 frozen corpus results are exactly equal to the captured dev.3
  baseline for paths, bounds, statistics and warnings.
- The untracked private image was selected by geometric bounds rather than
  contour index. Its reported small contours are curve-only under Balanced,
  Sharp and Smooth Detail, and no isolated small contour acquires a replacement
  line elsewhere in the setting matrix.
- All 107 companion tests passed against the universal dev.4 engine, including
  engine preference, backward compatibility and deterministic packaging.
- The standalone product-boundary audit, four release-metadata tests, package
  verification and whitespace check passed.

The unsigned universal engine is stored at
`.build/beztrace-0.1.1-dev.4/bin/beztrace` with SHA-256
`b2ceadc199f6e6b07429b21d839fac2443d3dbfda1920ea87ca3bd10bedcb9f9`.
The unsigned companion package is stored at
`.build/glyphs-companion-0.1.0-build11`; its deterministic archive
`beztrace-glyphs-0.1.0-build11-macos-universal.zip` has SHA-256
`1d56f8acc3f94660a077498a1dbf2ab9b7e1fbe3b4c1f3d6ad572ea9e783cde2`.
Read-only verification passed for its manifest, archive, payload and checksums;
native qualification remains `development-unqualified`. Dev.4/build 11 are not
installed, launched, signed, notarized or published, and no user font was
opened or modified.

### Source-only three-node follow-up

The source checkout subsequently added a universal final-output invariant of
at least three on-curve nodes per valid closed contour. Two-segment loops use
exact midpoint subdivision of the segment with the longest control polygon;
invalid and degenerate contours are not repaired. The corrected source passed
100 optimized Swift tests on arm64 and x86_64/Rosetta, with one intentional
maintenance skip, plus all 107 companion tests and the product-boundary and
release-metadata checks. The private nine-profile matrix has no two-node output
and no small-contour lines. All 100 frozen corpus paths, bounds, statistics and
warnings remain exactly equal to the preceding baseline.

No engine or companion version was bumped, rebuilt as a universal artifact,
repackaged, signed, notarized or published for this source-only follow-up. The
previous build-11 development link was installed under separate authorization,
but Glyphs was not relaunched; that installed payload does not contain this
follow-up.

## Build 12: stable engine compatibility

Source build 12 adds exact beztrace 0.1.1 compatibility and retains earlier
accepted versions. It changes version checks and distribution metadata only.
Native visible UI qualification, live installation/relaunch, signing and
publication remain separate; no companion is included in stable engine assets.

## Build 12 — 2026-10-05 engine handoff

Source and verified local unsigned package are 0.1.0 build 12. The ZIP SHA-256 is `6341e27f50a180b6b6258a19029942181d3c974c3a55c6c367097744db41212f`; packaging, payload inventory and checksums pass. All 107 contracts and isolated AppKit checks pass with the final stable 0.1.1 engine. The installed symlink still points to build 11, whose version contract rejects stable 0.1.1; the loaded build is not established here. Build 12 has no native-tested Glyphs builds and remains development-unqualified, unsigned, unnotarized and unpublished. No companion install/relaunch or user-font operation was performed.

See the [integration handoff](../../docs/GLYPHS_MCP_V2_HANDOFF.md) for exact installation instructions and the complete missing native/distribution work. Contract and fake-host checks do not qualify native acceptance.

## Build 13 — independent review 2026-10-05

The prepared lazy-image and deterministic cache timestamp fixes pass 113 tests
with stable engine 0.1.1. Bounded native backend checks cover placement, zero
width, replacement/Undo/Redo, stale images, cancellation, invalid options and
injected recovery faults. Installed VM UI evidence applies to the historical
build-13 candidate. Full installed UI and final committed-artifact qualification
remain incomplete; Intel is deferred. See [the detailed record](QUALIFICATION_BUILD13.md).
The candidate remains development-unqualified, unsigned and unpublished.

## Build 13 native follow-up and build 14

The committed build13 archive was installed and its loaded identity verified on
macOS14.6.1 arm64, Glyphs4.1.1/build4108, official Python3.14.6 without clearing
PythonCache. Twenty-three installed controller cases and foreground zero-width
mouse Trace/Done/native Undo/Redo passed. Saved preference reopen failed; a
separate native diagnostic confirmed wrapped numeric values were rejected.
Build13 fails that release gate. Historical raw receipts are retained under
`.build/companion-build13-qualification-20261005/followup-m39-m40` in the primary
checkout. Build14 corrects conversion at the native boundary; see
[its qualification procedure](QUALIFICATION_BUILD14.md) and final release report.


## Build 16 — master matching development

See [the build-16 qualification record](QUALIFICATION_BUILD16.md). Source and
unsigned packages extend qualified build 15 with neutral matching, file exchange,
detached native HOI and raster planning. Automated suites and detached native
backend checks pass. Visible installation acceptance and compiled-font export
remain pending; this is not a usable-milestone or release qualification.

### AppKit matching diagnostics — 2026-10-11

Branch `lit/master-matching`, macOS 26.7.1 (25G309), arm64, Python 3.14.6.
Scope: workspace source in an isolated real AppKit process with a fake host;
no Glyphs process, installation/relaunch, font file, save, or export access.

The restricted shell reproduces SIGABRT at `NSApplication.sharedApplication()`
in macOS `_RegisterApplication`, before companion controls are constructed.
Crash record: `Python-2026-10-11-120119.ips`, incident
`C50FEC9E-3D29-4756-BEC5-674E05E2C07F`. The identical minimal initialization and
ordinary smoke pass with authorized GUI access outside that shell sandbox.
`appkit_smoke_runner.py` now isolates native work in a child, reports signals and
the GUI requirement, preserves assertion/nonzero failures and times out instead
of terminating the parent. The restricted retry exits 1 with a clear failure;
it does not report success. Four runner regression tests pass.

The ordinary AppKit smoke passes its unchanged control/layout, live fake-host
tracing, validation, state and cleanup checks. The new matching smoke passes
**nine native checks** and **eight rendering cases**: real-engine Prepare;
read-only endpoint/midpoint/reversed-reference previews; Cancel; line and cubic
input refusals for both reference and target; structured segment/source-node IDs;
red segment/approximate crossing markers in Aqua and DarkAqua; source-half-only
drawing; clearing stale highlights; refusing to show fitted failure geometry;
disabled Apply/Export on refusal; window/timer cleanup. The native raster checks
measure 3,941–3,948 added red pixels per case and require pixels near both
segments and the analytical crossing. Cubic cases use collinear controls to
exercise the native cubic drawing branch with independently known geometry.
The host raises on Apply/write and fake layers/Undo state remain unchanged.

Actual screen and accessibility inspection verifies the visible matching panel,
controls, red source segments/marker and disabled Apply/Export. The native Details
dialog displays both locations, original nodes and coordinates; it was dismissed
and the owned window closed by the check. An initial computer-use lookup timed
out; binding the exact Python 3.14 app path resolves the multiple Python app
identities. View-cache PNGs do not capture every composited control and are used
only as custom preview evidence, not full-window screenshots. An initial
synthetic equal-lobed crossing hit the existing zero-area rejection before the
crossing check; the smoke fixture now uses unequal lobes. That failed attempt
was retained and is not counted as passing evidence.

Final companion suite: **144 tests, zero failures**. Source syntax and diff
checks pass. Engine behavior, tolerance and point caps are unchanged. Tested
matching UI SHA-256:
`84ed9ad8582dc03d41e993bd8e216a3e53aec892fcafb2ce480d47b2a02716df`;
preview SHA-256:
`6e1e4310a0a8006a620ebaead0a136b0f23168cdff8d218830d313b2bc0503c3`;
development engine SHA-256:
`901b7aaef703179df7c68e7d10ca93a4cb9f1bee44fae772510fd9b6be9a058f`.
All matching-module hashes, native results and images are in
`.build/glyphs-appkit-matching/report.json`. This establishes isolated native
AppKit behavior; installed Glyphs integration, actual font transactions,
save/reopen/export and Intel execution remain unqualified by this check.

### Live Glyphs panel — 2026-10-11

Tested inside the running **Glyphs 4.2/build 4201**, Python **3.14.6**, macOS
26.7.1 arm64. A new pathless font, **Beztrace Matching Disposable QA 2026-10-11**,
held two Weight masters and five synthetic glyphs: valid shifted starts,
reference/target line crossings and reference/target cubic crossings. The native
script route created only these disposable objects. The installed companion is
stable build 15 without matching; the unchanged workspace matching package was
temporarily loaded under `beztrace_matching_live_20261011` with the **real
MatchingHost**, not a fake host. No installation, plugin overwrite or app restart
occurred. This is live source-loaded panel evidence, not installed menu acceptance.
The matching UI, preview and engine hashes are the same as the isolated record
above; loaded source paths and hashes were read inside Glyphs.

Passed native/on-screen checks:

- A valid detached Prepare returns a four-node result and enables Apply/Export;
  moving the slider to 50 shows Weight 500. No Apply or export was invoked.
- All four source-crossing cases report the correct reference/target master,
  segments 0/2, line source node pairs 0→1 and 2→3 or cubic pairs 0→3 and 4→7,
  and the crossing at approximately (64.444444, 108.888889). Actual Glyphs
  screenshots show both red source segments and marker. The native Details
  dialog displays the structured locations and was dismissed.
- Each refusal produces no plan and disables Apply/Export. Settings invalidation
  clears diagnostic highlights/markers. A three-point ceiling rejects the
  four-point valid reference without raising the ceiling or changing tolerance.
- Native fingerprints for every source layer in all five QA glyphs, including
  widths, anchors and native flags, remain unchanged throughout verification.
- Closing the panel removes its timer. All script recovery workflows were
  settled without saving; the disposable font was discarded and closed, and
  the previously current document reactivated.

**One native preview defect remains:** after a successful shifted-start match,
leave the slider at 50, select another glyph, then rebind the shifted-start
source. Before matching, raw source nodes are interpolated by index; the two
different starts collapse the midpoint. `matching_preview.payload` calls
`commands(actual)`, and `contract.segments` raises **Degenerate segment**.
`useSelection_` catches this and clears the context, disabling Prepare for a
valid source. Resetting the slider to 0 and rebinding recovers. This is a failed
verification case, not a geometry rejection from the engine; source geometry,
tolerance, budgets and refusal rules are unchanged. No production fix is claimed.
The right-hand drawing on refused inputs is raw source interpolation, not a
successful fitted result; disabled Apply/Export and absence of a plan were
independently checked. Full panel acceptance is therefore not claimed.

The initial stale tab/preparation and uncertain repeated Edit-tab opening were
reconciled using fresh selection/context reads, without replaying an uncertain
Open. Two budget-harness assertions failed before a fresh raw inspection confirmed
the refusal; those failures remain in evidence and are not counted as passes.
Native evidence is `.build/glyphs-live-matching-panel/report.json`, and the
repeatable guarded probe is `scripts/live_matching_panel_probe.py`.

Existing open font files retain their before/after SHA-256 values:
`opf-logo.glyphs`: `5387024b4b463cc44de2829bbdee5cea369533524f0f7ac35b461698e52762a8`;
`LeftyNote-Bold700-Group01.glyphs`: `f32e4c34dee6aa52dc9edcd234b9014f60b6d4177925ef506882f92d965ca712`.
The already-dirty logo document remained dirty; its reported generation advanced
during the session, so these hashes establish disk preservation, not whole-font
in-memory equality. Every script was bound to the exact QA document and every
panel context/font identity checked against it. No existing font was saved,
discarded or targeted for edits. Native HOI remains disabled on 4201, and
installed-menu, Apply/Undo/Redo, save/reopen/export, Intel and release qualification
remain outside this test's scope.

### Source-linked development installation — 2026-10-11

The owner explicitly requested installation as a development symbolic link and
will save their work and restart Glyphs themselves. The actual Glyphs 4 path
`/Users/thierryc/Library/Application Support/Glyphs 4/Plugins/Beztrace.glyphsPlugin`
now links directly to this checkout's `Companions/Glyphs/Beztrace.glyphsPlugin`
(0.2.0-dev.1/build 16). The prior signed build 15 directory was moved intact to
`/Users/thierryc/Library/Application Support/beztrace/Plugin Backups/20261011T180844Z/Beztrace.glyphsPlugin`,
outside plugin discovery. All original file hashes match the preserved backup.
Source bundle validation and installed-link/content comparison pass.

The source default now selects the fresh universal diagnostics engine at
`.build/beztrace-0.2.0-dev.1-diagnostics/bin/beztrace`, SHA-256
`c15872c23d6e5e8ce2607e6977d7630bf506a7dd1da14529399c21de2efeb12a`.
Both arm64 and x86_64 slices were rebuilt from current Swift sources, with a
source-hash receipt. The prior correspondence engine and stable system engine
remain untouched. Two engine-selection regressions and four matching diagnostics
tests pass. An isolated AppKit check against the fresh universal engine passes
all nine checks and eight light/dark rendering cases; it uses a read-only fake
host and accesses no Glyphs process or font files. This does not qualify the
installed menu or cure the live midpoint preview defect recorded above.

No Glyphs restart, font Save, Apply or export was performed. Existing font-file
hashes match the two values in the live record. The running plugin remains the
previously loaded build until the user's restart; installed menu loading is
pending. The local installation/backup inventory is
`.build/glyphs-development-link-install/report.json`; isolated native evidence
is `.build/glyphs-development-link-install/appkit/report.json`.


### Matching dialog simplification — 2026-10-11

The owner requested a simpler native dialog with the selected master as target,
a previous/last-selected reference, a larger preview and an explicit Process →
Apply workflow. The current source-linked build 16 now opens at 900 × 760, with
an 852 × 416 centered preview (2.23 times the former preview area, over half the
main content area). The current foreground master is the target; reference
selection prefers a remembered different master on the same font, otherwise the
previous master in font order. In the supported two-master workflow this is the
other master. Opening an existing controller recaptures current selection.

The native accent/default button is Process before a result, Apply after a
verified result, and Process again after settings invalidate the proposal. Cancel
appears only while processing. The interpolation slider appears only with a
processed result. The main window holds the master choices and preview; Options
holds source mode, reference policy, fit tolerance, node limits and manual
correspondence. Image and unavailable repair controls are hidden when irrelevant.
Import/Export, current glyph and engine selection live in More. Successful
processing uses a short instruction; numerical reports remain in Details.

The previously recorded midpoint defect is fixed in preview preparation: raw
source outlines are never interpolated by unverified node index. The unprocessed
right-hand preview shows the target. Rebinding resets the slider and can process
either selected master at a midpoint. Invalid selection clears stale preview
geometry; invalidation removes the previous proposal and its diagnostics. Engine
geometry rejection, fit tolerance and point-budget values are unchanged.

All 148 companion tests pass, including four new presentation regressions.
The expanded isolated AppKit suite tests default master choices, native default
buttons, Process/Apply/invalidation state, options visibility and bounds,
midpoint rebinding, exact node-budget refusal, empty targets, four source
line/cubic refusals in light/dark appearances, fitted refusal, missing selection
and close/timer cleanup. Source fingerprints remain unchanged; the fake host
rejects native writes. Native reports and source hashes are under
`.build/glyphs-matching-ui-redesign/`.

Full-window computer-use inspection of the isolated Python app timed out; a
bundle identifier lookup also reported multiple installed Python apps. These
attempts are not counted as visual acceptance. NSView-cache PNGs substantiate
the custom preview rendering but omit some composited native controls; native
default-cell, accent color, visibility and layout assertions provide programmatic
UI evidence. Full installed menu/appearance acceptance remains pending the
user's restart. No Glyphs restart, existing font operation, Apply or font Save
was performed by this UI change. The existing development link points directly
to the revised source; the prior source bundle is preserved at
`.build/glyphs-panel-before-ui-20261011`. Stable distributions and the compiled
matching engine are unchanged.


## Build 17: unified mode dialog (2026-10-12)

Implemented on `lit/master-matching`, preserving the existing dirty worktree.
The 820 × 640 AppKit window replaces the matching Options window with an inline
inspector and four icon modes. Both native menu entries use the unified controller.
Single-image preparation now uses the existing detached API, followed by explicit
Apply; the historical immediate Trace/Done controller and released payload remain.

- 154 companion tests pass with the installed stable tracing executable and an
  absolute path to the existing diagnostics matching engine. The first run used
  a relative matching executable and failed the transport's required absolute-path
  check; `.build/glyphs-layout-tests.log` retains that failure. The passing log is
  `.build/glyphs-layout-tests-absolute.log`.
- The isolated AppKit/real-engine check passes all four modes (including a one-master font for Single image), settings visibility,
  no-op events, display tabs, interpolation endpoints, reference reversal, kept
  stale preview, secondary Update/primary Apply, cancellation and late results,
  source changes, point-budget refusals, line/cubic diagnostics in light and dark,
  preference loading/persistence via a test seam, idle Cancel and timer cleanup.
  The read-only fake host forbids Undo, installation and recovery writes; it never
  imports GlyphsApp or reads font files. This is not installed-Glyphs qualification.
- Final native evidence is `.build/glyphs-layout-acceptance/report.json`.
  Offscreen AppKit bitmaps omit some composited controls on macOS 26; actual
  WindowServer captures were used for visual review. The corrected capture is
  `.build/glyphs-layout-final/native-window.png` (inactive-window appearance).
- Product-boundary checks and local unsigned build-17 packaging pass. The existing
  SDK loader/license/source hashes are validated by the repository packager. The
  generic installed skill scaffolder rejects this plugin's unchanged pinned
  `GlyphsSDK-SOURCE.json` against its own template; that mismatch was not corrected
  by replacing the project's reviewed provenance.

The proposal key includes effective settings, mode, masters, engine and imports.
Presentation-only changes do not invalidate it. External source edits revoke Apply,
while both application APIs independently revalidate before touching a font.
Only a successful current result enables Apply; HOI refusals remain blockers.
No standalone engine source/schema changes, release changes, installation, Glyphs
relaunch, font save, signing, notarization or publication occurred as part of this
UI revision.
Exactly two masters/one axis remain the paired-mode limit; no unsupported add-master
control is shown. Single-image mode retains its own ordinary destination checks.


## Build 18: layout review against the selected mockup (2026-10-12)

The review captured a fresh isolated native window before editing it. Compared
with the selected image, build 17 had horizontal icons, exposed axis metadata,
a glyph heading, a mode explanation and utility buttons competing with Apply.
The 820 × 620 revision stacks native SF Symbol icons above mode labels, aligns
source selectors showing only master names, groups preview/inspector in lightly
bordered native surfaces, and moves reference policy and utility actions into
Advanced. The percentage is visible; the exact axis value remains a tooltip.
The footer contains only secondary Update Preview, Cancel and primary Apply.
Actionable failures remain visible, with Error Details available in Advanced.

154 companion tests pass (`.build/glyphs-layout-build18-tests.log`). Isolated
AppKit checks pass (`.build/glyphs-layout-build18-final-review/report.json`), including
native mode-button clicks and clicking the selected mode without invalidating
its result. Native drawing, dark/light diagnostics, detached preparation,
source guards, cancellation, saved preferences and all four modes remain covered.
The reviewed image/image screenshot uses the owned R regular/bold PNG fixtures
and real matched outlines, with fit tolerance edited to show Update enabled and
Apply disabled. Evidence is under `.build/glyphs-layout-build18-final-review`.
These are fake-font AppKit checks; installed Glyphs qualification remains pending.
The generic scaffolder's pinned SDK metadata mismatch noted for build 17 is
unchanged. The project packager validates the preserved loader/source/license
hashes instead. No engine or released payload changes, installation, relaunch,
signing or publication are part of this refinement.


## Build 19: native text alignment and spacing (2026-10-12)

Form labels now use their intrinsic text height and are vertically centered on
AppKit's control title rectangles. Reference/Target and inspector field labels
are right-aligned with 12-point label/control gaps. Both source dropdowns have
equal widths; Single image centers its lone source group. Inspector rows use a
consistent rhythm, with the first control aligned to the preview tabs. Surface
insets and gutters are 12 points; the source/mode gap is 16 points and the
body/footer gap is 12 points.
Mode tiles have equal 4-point internal margins. Slider endpoint labels are
centered vertically on the slider. Percentage text is hidden while an actionable
status occupies the same lower preview area, preventing text overlap.

154 companion tests pass in `.build/glyphs-layout-build19-tests.log`. The isolated
native checks, including all modes, Advanced geometry, dark/light drawing,
source guards, cancellation and saved preferences, pass in
`.build/glyphs-layout-build19-spacing/report.json`. The actual window capture is
`.build/glyphs-layout-build19-spacing/native-window.png`, reviewed with the owned
R fixtures. Update/Apply behavior is unchanged. This is an unsigned source/local
package revision; no installation or native Glyphs qualification is claimed.

## Build 20: completed dialog layout (2026-10-12)

The final candidate includes the reduced 12-point body/footer gap and keeps all
three footer buttons on one baseline. All four modes and their relevant settings,
the neutral two-arrow Update Preview button, and the primary Apply action retain
their tested behavior. The companion build advances to 20 so a later installation
cannot reuse build 19's timestamp-based external bytecode cache.

All 154 companion tests passed in `.build/glyphs-layout-build20-tests.log`.
Isolated AppKit checks with real tracing/matching engines passed for all modes,
stale-source guards, cancellation, saved preferences and diagnostic drawing.
Evidence is in `.build/glyphs-layout-build20-final/report.json`; the reviewed
window capture is `.build/glyphs-layout-build20-final/native-window.png`.
The standalone product-boundary audit also passed.

The local unsigned candidate is staged under
`.build/glyphs-companion-build20-final-candidate`, with a second reproducibility
copy under `.build/glyphs-companion-build20-final-repeat`. Installed Glyphs
transactions, Undo/Redo, save/reopen and export acceptance remain outside these
fake-font checks. No live installation, relaunch, signing or publication occurred.

## Build 21: Apply-only hint preservation (2026-10-17)

Removed the blanket hint refusal from matching context capture and revalidation.
Detached preview layers omit source hints; live layers and hints remain intact.
Immediately before Apply, both masters are preflighted using the exact native
source outline and explicit contour/node mappings. Raster-boundary indices are
never treated as destination node indices. Unchanged layers retain their native
paths, nodes and hints. Changed layers receive hint copies attached to their
actual installed nodes, with native settings and absolute values preserved.
Removed/retyped nodes, ambiguous or unsupported attachments and changed
corner/cap adjacency refuse Apply before Undo begins. Such a refusal retains
the reviewed preview and interpolation controls. Hint edits invalidate a plan.
Readback checks hint references/settings, and recovery restores paths and hints
together if either master fails installation or verification.

Local evidence:

- All 169 companion tests pass in `.build/glyphs-hints-build21-final-tests.log`.
  The 15 focused hint tests also pass after the final recovery refinement in
  `.build/glyphs-hints-build21-focused-final.log`. These use identity-aware native
  doubles and real engine output; they do not qualify installed native hints.
- Isolated AppKit checks pass in `.build/glyphs-hints-build21-appkit/report.json`,
  including retaining the preview/slider after an Apply-only hint refusal.
- The standalone product-boundary audit and whitespace checks pass.
- The requested `scripts/check_local.sh .build/local-checks-hints-build21`
  invocation passes dependencies, then stops at its existing Bash empty-array
  error: `ASAN_ARGS[@]: unbound variable` (line 28). It does not establish a full
  repository qualification result. The scoped companion checks above ran directly.
- The generic skill scaffold validator still rejects the unchanged pinned
  `GlyphsSDK-SOURCE.json` attribution format. The repository packager verifies
  the preserved SDK loader hash, license, schemas and payload instead.

The unsigned local build-21 package is staged in
`.build/glyphs-companion-build21-hints-candidate`, with the repeat build in
`.build/glyphs-companion-build21-hints-repeat`. Live installation, loaded-build
verification, native hint/Undo/Redo/save/reopen/export acceptance, signing,
notarization and publication were not performed.
## Build 22: verified fitting and joint smoothing integration (2026-10-17)

Local source build 22 adds **Smooth compatible joins** to the three paired modes.
The existing engine uses verified Levien-first fitting with refined least-squares
fallback. The optional `smoothJoins` matching step runs one target-only projection
after fitting and envelope constraints, preserving the matched reference,
on-curves, flags, node types/order/counts and point ceilings. Vector verification
uses the original target; raster verification uses the retained unsimplified,
placed boundary. There is one final 201-position sweep, with no production graph
selection or tolerance relaxation. Native HOI is an explicit Advanced option.

- 21 focused Swift smoothing/integration tests pass, including original raw
  raster measurement, blocking refusal and unchanged default wire output.
- All 175 companion tests pass; the final 57 matching-specific tests pass after
  import review was made read-only for the recorded smoothing choice.
- The isolated AppKit harness passes 22 checks, including all four modes, the
  smoothing toggle, stale previews, Apply/refusal guards and imported settings.
  Captures and module hashes are in `.build/joint-app-appkit-accepted`. This uses
  a fake host and accesses no Glyphs process or font files.
- The actual matching command reproduces all 12 frozen smoothing jobs: identical
  accepted geometry/reports and refusal bounds, with byte-identical arm64/Rosetta
  output. The full 28-case/1260-configuration benchmark preserves historical
  geometry, acceptance and smoothing reports. Evidence is in
  `test-work/curve-benchmark-20261017-app-integration` and
  `test-work/curve-benchmark-20261017-app-full`.
- All 18 existing pair-workflow jobs pass on both architectures and are
  byte-identical; see `.build/joint-app-pair-comparison.json`.

The unsigned universal engine is
`.build/beztrace-0.2.0-dev.1-smoothing/bin/beztrace`, SHA-256
`f445ef91f33c5301bd3434a569351d7cf0085699f35a040a9d469730c88b1c1b`.
The local matrix is recorded under `.build/joint-app-local-checks`; the sanitizer
helper remains blocked by macOS platform policy. Native arm64 and Rosetta each
pass 194 tests with two skips and zero failures; 26/27 source commands pass.
The existing dirty worktree
prevents clean qualification. Rosetta does not qualify native Intel execution.
No live installation, Glyphs relaunch, user-font edits, signing, notarization or
publication is performed. Earlier build/release records remain historical.

## Build 23: contextual sidebar groups (2026-10-17)

Local source build 23 removes the unified dialog's global Advanced disclosure.
Image/Curves, Reference, Fitting, Correspondence and Interpolation groups appear
only in relevant modes. Manual correspondence exposes contour/start selectors;
shared subdivision exposes the growth allowance; selected native HOI correction
exposes its thresholds. Review hides manual overrides. Additional actions stays
available in each mode. The fixed preview/window size is preserved; expanded
controls scroll within the inspector. The legacy trace preference format remains
compatible, including its stored disclosure preference for the older trace panel.

- All 175 companion tests pass. The final real-AppKit fake-host harness passes
  23 checks, including all four actual-engine routes, row bounds/overlap, visual
  tab order, dependent controls, no-op presentation changes, stale previews,
  imported smoothing choices and saved trace settings. Evidence and captures are
  in `.build/grouped-sidebar-appkit-final` and
  `test-work/sidebar-groups-20261017`.
- No fitting, smoothing, verifier, schema, tolerance, reference or node-policy
  change is introduced. The engine SHA-256 remains
  `f445ef91f33c5301bd3434a569351d7cf0085699f35a040a9d469730c88b1c1b`,
  identical to the build-22 integration benchmark. The frozen benchmark records
  remain unchanged; the UI harness exercises the existing engine in all modes.
- The required local check is recorded in `.build/grouped-sidebar-local-checks`;
  its results remain separate from native Glyphs qualification. The existing
  dirty worktree prevents clean qualification, and the earlier build-22 record
  documents the sanitizer helper's macOS platform-policy limitation.
- Unsigned local packaging is staged in `.build/glyphs-companion-build23-sidebar`
  and independently repeated in `.build/glyphs-companion-build23-sidebar-repeat`.
  Both are subject to manifest, ZIP and payload verification.

No Glyphs process or font files were accessed by these UI checks. No installation,
relaunch, font edits, signing, notarization or publication was performed. Historical
release and build-22 engine/benchmark evidence is preserved.

## 0.2.0/build 24 version promotion (2026-10-17)

The final-version source uses engine 0.2.1 and companion 0.2.0, companion build 24.
Explicit companion compatibility includes 0.2.0 and 0.2.1 while retaining all earlier
accepted versions. The source-checkout executable path points to the newly
built local universal engine. The approved sidebar and geometry algorithms are
unchanged. The incremented build invalidates the external Python bytecode cache.

Local preparation uses `.build/beztrace-0.2.1`,
`.build/glyphs-companion-0.2.0-build24-final` and a fresh repeat-package directory.
Verification results, checksums, the architecture comparison and exact source
hashes are recorded with the local artifacts. The required local matrix uses
`.build/final-0.2.1-local-checks`. Historical build-23 and benchmark records are
retained; the new executable must reproduce their geometry and refusal limits.

This version promotion does not establish installed/loaded Glyphs qualification,
clean-source provenance, signing, notarization, installation or publication.
The outstanding gates are listed in the [release record](../../docs/RELEASE_0.2.1.md).

## Build 25: native getter-backed metadata (2026-10-17)

Additional detached native hint acceptance on Glyphs 4.2/build 4202 found that
GSHint metadata can be exposed as raw zero-argument Objective-C getters. Build 24
compared the selector description, whose identity differs across copied hints,
and refused Apply; its recovery fingerprint also failed. This was observed only
on a newly created detached synthetic font. No user font was accessed or changed.
The first two harness attempts had separate fixture/API errors; their logs are
retained independently from the third attempt's actual product failure.

Build 25 resolves getter-backed values before normalization and comparison,
retaining fail-closed native read errors. Regression cases compare copied getter
objects, detect real metadata changes and propagate unavailable getter failures.
The build increment prevents stale external Python bytecode. Engine 0.2.1,
fitting, smoothing, error limits, references and node compatibility are unchanged.
Native fixture evidence and final package hashes remain in the external release
qualification records. Build-24 source/package evidence remains historical and
does not qualify build 25.

The same native fixture exposed GSHint.copy() omitting custom userData on
Glyphs 4.2. Build 25 copies that dictionary before attachment, transfers each
prepared hint once, snapshots recovery dictionaries explicitly, and includes
stem/alignment/userData in preserved-state checks. Unit coverage includes native
copies omitting dictionaries and a guard against metadata setters on attached
hints. Actual native Apply now retains those values. Headless hint Undo raises
a GSUndoManager grouping error and remains unqualified pending the authorized
installed-document acceptance; it is not counted as passing native Undo.
