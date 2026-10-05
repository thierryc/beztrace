# Handoff to the Glyphs MCP coding agent

## Boundary

Implement optional companion setup in the Glyphs MCP repository as a separate
task. This repository supplies a normal Glyphs plugin and an external CLI
contract. It adds no bridge protocol, MCP tool, private import, or runtime
registration in the bridge's companion catalog. The user can use the menu
without running Glyphs MCP.

## Manifest v1

Validate `companion-manifest.json` against `manifest-v1.schema.json`. Treat
artifact paths as relative to the manifest's distribution location. Require
version/build, bundle identity, platform/Python requirements, exact engine
compatibility, archive SHA-256/size, and payload inventory. The `payloadSha256`
is SHA-256 of the inventory encoded with Python JSON `sort_keys=True` and
`separators=(',', ':')`, UTF-8. Inventory is sorted by relative path.

`sourceRevision` names the Git base; `sourceTreeDirty` explicitly marks builds
with local changes. The payload inventory identifies their actual bytes.
`qualification` distinguishes declared support from native-tested builds.
The 0.1.0 build-6 artifact is unsigned, unnotarized, and native-unqualified. Production
setup must refuse it unless the user explicitly chooses a development install.
Do not infer trusted distribution from a checksum alone. A future published
manifest must come from a trusted release and agree with verified signatures.

## Install

1. Inspect Glyphs 4's app bundle ID, version/build, CPU, OS, and configured Python
   runtime. Resolve its actual Application Support directory. The install path
   is `<glyphs4ApplicationSupport>/Plugins/Beztrace.glyphsPlugin`.
2. Resolve the separate engine dependency. Verify the existing published engine
   release's checksums and Developer ID signature; provision it through its
   documented installer only with the required user authorization. Do not rebuild
   or re-sign the released engine as part of plugin installation.
3. Download the companion archive only after a release is authorized. Validate
   its hash and size before extraction. Reject absolute paths, `..`, symlinks,
   duplicates, extra files, and any extraction path outside staging. Validate
   every payload checksum and executable bit and inspect Info.plist identity.
4. Check the actual bundle signature/team and notarization evidence required by
   the distribution channel. Manifest booleans alone are not proof.
5. Stage beside the destination, preserve any existing owned bundle, and move
   the verified bundle into place. Do not overwrite another plugin identity.
6. Explain that a relaunch is needed and request it under the app's authorization
   flow, preserving unsaved work. Never claim file installation proves loading.

## Detect, update, and remove

Detection reads `dev.beztrace.glyphs`, bundle short version and build, payload
hashes, engine version, and compatibility. Report installed and loaded states
separately. Loaded verification requires the menu/window and revision evidence
from an authorized native check; this plugin does not advertise a bridge endpoint.

Compare semantic version and numeric build. Stage updates and validate them
before replacement, retaining the prior bundle until the new revision is
qualified. Rollback restores that owned bundle and requires another relaunch.
No self-update or network task runs inside Glyphs.

Removal deletes only the manifest-owned plugin after verifying its identity.
Leave the shared beztrace CLI, fonts, and other plugins intact. The loaded code
remains until Glyphs quits. Do not remove a shared engine as a side effect.

## Future tracing MCP adapter

Call `beztrace --version`, then `beztrace trace - --format json --json-errors`
with bounded image bytes on stdin. Consume JSON schema 1/pathDataVersion 2;
verify source hash, engine version, finite geometry, cyclic cubic ordering,
closure, counts, and bounds. Keep stdout separate from stderr and enforce
cancellation, timeouts, and resource bounds.

JSON is Y-up; each cubic ends in a `curve` node preceded cyclically by exactly
two `offcurve` nodes. `line` endpoints have no preceding off-curves. Preserve
smooth flags and outer/counter direction. Do not import the display-oriented SVG.

Choose one placement owner: request explicit CLI placement and use the returned
geometry directly, or request neutral geometry and apply one consumer transform.
The native plugin uses the second approach. Never transform an already placed
result again. Bind the intended document/glyph/owning layer before tracing and
revalidate before application. Use the MCP adapter's existing, separately
qualified recovery and path-mutation workflow; the plugin's undo group does not
extend to an MCP operation.

## Build 5: canvas workflow and placement API

The command is **Path → Beztrace…**, distinct from the built-in Glyphs filter.
The 280 × 190 panel exposes Auto/manual Threshold, Invert, image choice and Trace.
Trace inserts immediately at the native canvas image's transform with Undo.
There is no panel auto-sizing or separate Apply step.

Use version **0.1.0** and numeric build **5** to detect this revision. Rebuild the
exact development-link payload; changing workspace Python files alone does not
update a packaged link. A relaunch is needed before calling it loaded.

The [Python placement API v1](AGENT_API.md) prepares a batch without font writes,
then places native images in explicitly resolved existing layers. It retains
conservative metric sizing internally. It never traces paths into a font or adds
an MCP endpoint. Agents must review its completion/partial-failure report and
respect their own mutation authorization; asynchronous preparation is not
permission for a later write. Installer metadata and the engine contract remain v1.

## Development engine compatibility

Build 6 accepts exact versions `0.1.0` and `0.1.1-dev.1`. The CLI version probe
and JSON engine version must agree. The latter is a development prerelease at tag `v0.1.1-dev.1`,
not an artifact available from the v0.1.0 download URL. Provision its engine ZIP
only from its own prerelease, and verify the associated checksums and metadata. The engine stays outside the plugin bundle; its local build
directory includes source fingerprints, platform metadata and checksums.

The normal default executable and shared-engine removal policy are unchanged.
For local qualification, select the development executable explicitly through
Choose Engine or pass its absolute path to `prepare_imports(engine=...)`.

## Build 7: interactive trace

Local development build 7 adds Trace → Done, live threshold/invert updates and
a manual slider plus numeric input. Choose Image is removed from the panel;
image import and full tracing remain available through the Python agent API.
Detect numeric build 7 and verify payload hashes. This build is unsigned and
is not a published replacement for build 6.

## Build 8: expandable quality controls

Local development build 8 keeps the default panel compact at 320 × 210 points
and expands the same window to 320 × 408 points through an Advanced disclosure.
The expanded controls expose Balanced, Sharp and Smooth Detail presets and the
existing engine options for accuracy, smoothing, corner sensitivity, grid,
minimum contour area and raster refinement. Valid changes use the same 150 ms
live-retrace debounce; incomplete text never replaces the last valid settings.

Settings are stored in the versioned
`dev.beztrace.glyphs.trace-settings-v1` defaults dictionary. Reset Trace Settings
restores Auto threshold, Invert off, the Balanced advanced values and a collapsed
window. Detect numeric build 8 and verify payload hashes. This build is unsigned,
development-unqualified and is not a published replacement for earlier builds.

## Build 9: safe quality-control boundaries

Local development build 9 accepts engines `0.1.0`, `0.1.1-dev.1` and
`0.1.1-dev.2`, requiring the version probe and JSON result to agree. In a source
checkout it prefers the local dev.2 engine, whose final deterministic handle
rounding retains the preceding safe handles when an integer candidate would
violate geometry validation. The companion clamps Smoothing slider quantization
to its documented 0.25 minimum. Numeric input, persistence, presets and the
150 ms retrace policy are unchanged.

Detect numeric build 9 and verify payload hashes. Dev.2 and build 9 are unsigned
local artifacts; no publication, signing or notarization is authorized.

## Build 10: topology-safe Grid output

Local development build 10 accepts engines `0.1.0`, `0.1.1-dev.1`,
`0.1.1-dev.2` and `0.1.1-dev.3`, preferring dev.3 from a source checkout. The
engine keeps a fully validated no-grid contour whenever the requested Grid
candidate would make the complete outline invalid. The JSON contract is
unchanged; its existing `warnings` array records each fallback, and the panel
and agent trace result surface that warning after successful application.

Build 10 also refines the native panel to 300 × 210 points collapsed and
300 × 410 expanded with Auto Threshold. Preset and Invert image remain visible;
Threshold is the first unindented control under a right-aligned Advanced Options
disclosure. Manual Threshold adds 24 points, and inline numeric validation adds
18 points only while needed. Every transition preserves the window top edge.
Invalid input suppresses retracing and restores the last valid value when editing
ends; progress and global engine/destination failures remain in the footer.

Detect numeric build 10 and verify payload hashes. Dev.3 and build 10 remain
unsigned, development-unqualified local artifacts.

## Build 11: small convex-curve correction

Local development build 11 additionally accepts `0.1.1-dev.4` and prefers it
from a source checkout. Dev.4 prevents meaningful curved quadrants on small
convex contours from becoming straight chords. The companion UI, trace options,
schema v1 and path data v2 remain unchanged.

Detect numeric build 11 and verify payload hashes. Dev.4 and build 11 remain
unsigned, uninstalled and development-unqualified local artifacts.

## Current build 13 qualification handoff

The current source candidate is 0.1.0/build 13 and accepts stable engine 0.1.1.
It corrects lazy default-crop capture and assigns distinct deterministic ZIP
member timestamps per build to invalidate external PythonCache. The earlier
build descriptions above are historical. See the
[qualification record](QUALIFICATION_BUILD13.md) for bounded evidence and gates.
No committed/published build-13 source URL or stable plugin download is established
by an uncommitted package. Keep the existing public source pin until a new source
checkpoint is authorized and remotely available. Require exact final archive,
manifest and checksums; native-tested status, signing and notarization are separate.
