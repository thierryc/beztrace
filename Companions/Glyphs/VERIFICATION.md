# Verification record — companion 0.1.0, build 2

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

## Native and release status

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
