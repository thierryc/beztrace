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
The 0.1.0 build-2 artifact is unsigned, unnotarized, and native-unqualified. Production
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

## Build 2 user interface and sizing

This revision replaces the large window with a floating native inspector, explicit
metric presets, and a cached edit-view overlay. Detect numeric build **2** as well
as version **0.1.0** when offering updates from build 1. No engine or tracing JSON
contract changed. Loaded revision evidence includes **⋯ → About Beztrace 0.1.0 (2)**.

Auto sizing is deliberately conservative; the app should not advertise general
case recognition or optical correction. The pure `placement.py` rules and
`preview.py` transform document the consumer policy separately from the neutral
engine. A future MCP adapter may use equivalent rules after obtaining current
layer/master metrics, but must capture/revalidate its own target and metadata.
The overlay is transient UI and is never part of the returned tracing contract.
