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
