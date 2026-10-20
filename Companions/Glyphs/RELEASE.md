# Companion release procedure

The packaging script produces unsigned candidates; signing and notarization are
separate steps. Current published engine 0.2.2 and companion 0.2.1/build 26 are
qualified at frozen source `64c9c47`; see [the release record](../../docs/RELEASE_0.2.2.md).
Future distributions require their own authorization and qualification.

## Local reproducibility

Run `scripts/package.py --output <new-directory>` from this directory, twice
into different empty destinations. Compare the ZIP and every payload hash.
ZIP timestamps are deterministic for each companion build and source permissions
are normalized. Increment the companion build for every changed distribution:
Glyphs caches timestamp-based Python bytecode outside the plugin bundle. Reusing
a timestamp for equal-size updated source can load the preceding build. Use the same
Python/zlib toolchain when comparing compressed bytes. Signing timestamps and
Apple notarization are separate, non-reproducible external steps.

The vendored loader must retain the exact SDK checksum in the source tree.
Packaging validates it before copying. A signed staging copy will have different
bytes and must never be copied over the pinned source loader. Run the development
skill scaffold validator against source before signing; use codesign verification
against the staged signed bundle afterward.

## Authorized distribution steps (not executed by packaging)

1. Complete the native qualification checklist for the exact artifact and record
   each tested Glyphs build. Verify Python runtime setup on a fresh host, Apple
   Silicon loading, separate Rosetta evidence, universal slices and UI accessibility.
   Native Intel loading is deferred under the owner’s 2026-10-20 instruction until
   hardware is available; record it as untested, owner-waived. Freeze the source revision,
   plugin version/build, SDK provenance, and SBOM.
2. Obtain separate authorization for signing, notarization, upload, publication,
   installation, and relaunch as applicable. Select the existing project's
   Developer ID Application identity and notarization keychain profile. Never
   replace or re-sign any published engine artifacts, including stable 0.1.1.
3. In a separate staging directory, sign the plugin's executable and bundle
   inside out, then verify all code and resources:

   ```sh
   codesign --force --options runtime --timestamp --sign "$BEZTRACE_APPLICATION_IDENTITY" \
     "$BEZTRACE_PLUGIN_STAGE/Beztrace.glyphsPlugin/Contents/MacOS/plugin"
   codesign --force --options runtime --timestamp --sign "$BEZTRACE_APPLICATION_IDENTITY" \
     "$BEZTRACE_PLUGIN_STAGE/Beztrace.glyphsPlugin"
   codesign --verify --strict --verbose=2 "$BEZTRACE_PLUGIN_STAGE/Beztrace.glyphsPlugin"
   codesign -dv --verbose=4 "$BEZTRACE_PLUGIN_STAGE/Beztrace.glyphsPlugin"
   ```

4. Archive the signed bundle with `ditto -c -k --keepParent`, then submit that
   archive through the existing `xcrun notarytool submit ... --keychain-profile
   "$BEZTRACE_NOTARY_PROFILE" --wait` workflow. Record Apple's accepted submission
   and validate the exact signed archive on a clean Gatekeeper-enabled host.
   ZIP archives cannot be stapled. Do not claim a stapled ticket for this format;
   if an offline-stapled carrier is needed, qualify a separately authorized signed
   installer/DMG and its stapled ticket.
5. Recompute the signed payload inventory, SPDX binary checksums, archive size,
   checksums, and manifest *after* all signing changes. Record the actual verified
   Team ID and notarization receipt; set `developer-id-verified` and
   `accepted-verified` only with evidence. Do not run the unsigned package builder
   over signed staging: it intentionally rebuilds the unsigned source payload.
6. Re-run manifest/archive verification and native install/update/rollback/remove
   checks against those final bytes. Publish with an independently versioned tag
   such as `glyphs-v0.1.0` only after explicit publication authorization.

No credentials, identities, or signing commands run automatically from environment
variables in the companion build. The engine release remains a separate product.

## Development prerelease authorized 2026-09-28

The owner requested commit, merge and GitHub publication of the tested engine
correction and companion build 6. Distribute these current development artifacts
under the engine's `v0.1.1-dev.1` GitHub **prerelease**, with a separately versioned
`beztrace-glyphs-0.1.0-build6-macos-universal.zip`. Keep stable 0.1.0 as the latest
stable release. This does not qualify the companion for stable distribution.

Build both artifacts from the clean merged revision. Use
`scripts/build_development_engine.py` for the engine and this companion's package
builder for the plugin. Include both manifests, the companion manifest schema,
engine source/binary SPDX SBOMs, and top-level SHA-256 checksums. The companion
ZIP contains its own SPDX SBOM and licenses. Keep the original published 0.1.0
artifacts unchanged. No Developer ID signing or notarization is performed for
this explicitly labeled development distribution; record that status in its
metadata and release notes.

Publishing workflow: prepare and verify all assets, create a draft prerelease
at the merged commit, verify its tag target and uploaded asset checksums, then
publish without marking it latest. Never upload the private reproduction image,
local archives, font documents, caches or installation receipts. Native backend
checks and automated tests must be distinguished from pending full in-app UI
qualification in the notes. A subsequent stable release still requires the
qualification and signed-distribution steps above.

## Local dev.2/build-9 boundary

Engine 0.1.1-dev.2 and companion build 9 are local unsigned development
artifacts for the handle-rounding and Smoothing-slider corrections. They may be
built, packaged, installed and tested under their explicit task authorization,
but the dev.1 publication authorization above does not authorize uploading,
tagging, signing, notarizing or publishing dev.2/build 9.

## Local dev.3/build-10 boundary

Engine 0.1.1-dev.3 and companion build 10 are local unsigned development
artifacts for topology-safe Grid cleanup and warning propagation. They may be
built, packaged, installed and tested under their explicit task authorization,
but no prior authorization permits uploading, tagging, signing, notarizing or
publishing dev.3/build 10.

## Local dev.4/build-11 boundary

Engine 0.1.1-dev.4 and companion build 11 are local unsigned development
artifacts for the small convex-curve correction. They may be built and packaged
under the explicit task authorization, but installation, relaunch, user-font
edits, uploading, tagging, signing, notarization and publication remain
unauthorized.

## Build 13 independent qualification

Build 13 is an unsigned, unpublished candidate. The bounded
[qualification record](QUALIFICATION_BUILD13.md) separates automated checks,
detached native objects and installed UI evidence. Intel remains deferred.
Do not set a fully qualified native build or stable status for partial results.

Obtain local commit authorization before freezing provenance. Rebuild twice from
that clean source revision into fresh directories; verify every payload hash,
ZIP timestamp, manifest, SBOM, schema and checksums. Qualify the exact resulting
archive, including installed and loaded identity. Documentation and the generated
SBOM can change archive bytes even when executable Python is unchanged; a prior
build-13 receipt does not establish that the final archive was installed.

Provide Glyphs MCP a source URL only when the named revision is actually
available remotely under separate push authorization. Until then provide the
local patch, tests, package, manifest, checksums and explicit pending status.
The published stable engine's signature and notarization never qualify this plugin.

## Build 14 publication authorization — 2026-10-05

The owner requested the preference fix and GitHub publication of the latest
companion. Publish build14 as an independently tagged unsigned development
prerelease, `glyphs-v0.1.0-build14`, never latest. Freeze clean source, reproduce
twice, attach the manifest/schema/SBOM/checksums and bounded qualification report,
and verify anonymous downloads. Full native and signed distribution gates are
not waived. Preserve all engine tags/assets and historical companion bytes.

## Build 15 independent signing authorization — 2026-10-05

The owner explicitly requested signing and the official companion release. This
authorizes use of the existing Developer ID identity and Apple notarization
profile, companion source commits/pushes, GitHub assets and publication. The
owner separately instructed bypassing native Intel testing because no recent
Intel Mac is available. Record Intel as **untested, owner-waived**, with Apple
Silicon as the native qualification scope. This exception does not waive other
native checklist items. Preserve the published engine and earlier companion
release bytes. Build 15 changes only release wording in About and its identity;
build 14 signed candidates and Apple receipts remain historical artifacts.


## Build 17 local UI candidate

Build 17 introduces the unified four-mode detached preview dialog. It increments
only the companion build, preserving engine and published companion artifacts.
The deterministic archive timestamp advances with the build to avoid stale
Glyphs PythonCache entries. Source/tests and an unsigned local package are prepared;
installed native qualification, signing, notarization and publication are separate.
See [verification](VERIFICATION.md) and [native acceptance](NATIVE_TESTING.md).


## Build 18 local layout refinement

The simplified 820 × 620 dialog follows the selected mockup more closely with
stacked mode icons, preview/inspector surfaces and only three footer actions.
The independently numbered unsigned candidate preserves the existing mode APIs,
preview validation, saved trace settings and released bytes. See verification
for local checks; installation and native Glyphs acceptance remain separate.


## Build 19 local spacing refinement

Build 19 corrects native label/control text alignment and standardizes pane,
source-row, inspector and footer spacing. The unsigned local package retains
all four modes and the preview/application contracts. Native Glyphs installation,
acceptance and release gates remain separate.

## Build 20 completed layout candidate

Build 20 includes the final 12-point gap between the preview surfaces and footer
buttons. It preserves the four modes, relevant settings, vertically centered
labels and neutral Update Preview action, with the primary accent reserved for
Apply. The build advances to invalidate external Glyphs bytecode caches when
this changed payload is loaded. Packaging remains local and unsigned; installed
Glyphs acceptance and release gates remain separate.

## Build 21: hints during matching

Hints no longer prevent detached matching previews. Apply preflights both
masters before opening an Undo group, keeps unchanged paths and their hints,
and transfers affected hints only through explicit source-node correspondence.
Absolute hint values and native settings are retained. Unsupported attachments,
removed/retyped nodes and changed corner/cap adjacency refuse Apply while
leaving the preview available. Changed paths and hints share the same recovery
transaction. This is a local unsigned candidate; installed Glyphs acceptance
and distribution remain separately gated.

## 0.2.0/build 24 local final-version preparation

The owner requested final version 0.2.0 on 2026-10-17. Build 24 promotes the
companion identity and promotes the enhanced engine to 0.2.1 and adds explicit 0.2.0/0.2.1 engine compatibility, retaining
all earlier supported versions. The existing source, SDK loader and published
release bytes are preserved. The version number does not qualify an unsigned
package as a stable release. See the [release preparation record](../../docs/RELEASE_0.2.1.md).

Produce unsigned packages twice into fresh destinations, verify every byte and
record source provenance. Native installed/loaded acceptance, a clean reviewed
source revision, the current architecture/performance gates, signing, notarization,
installation and publication remain required. This request does not perform
Apple uploads, GitHub publication, font edits, installation or relaunch.

## Build 25 native qualification correction

Within the approved source-freeze/native-acceptance iteration, build 25 corrects
native getter-backed hint metadata comparison on Glyphs 4.2. The actual Apply
and recovery failure on a disposable fixture blocks build 24 from release.
Reproduce and qualify build 25, keeping prior candidates and failure logs.
The engine version remains 0.2.1 and the companion version remains 0.2.0.
Build 25 also preserves custom hint userData omitted by the native copy operation,
including recovery snapshots. An actual installed-document Undo/Redo pass is
required; the headless hint Undo grouping failure is retained as excluded evidence.

The subsequent installed UI acceptance passes Undo/Redo, Apply/recovery,
fresh-file save/reopen, neutral import and compiled interpolation on Apple
Silicon / Glyphs 4.2 build 4202. The exact unsigned archives reproduce from clean
source `217dcc0aad50a4c4a6b7e8c65e6bacc0931e2054`. See
[build 25 qualification](QUALIFICATION_BUILD25.md) for scope and limitations.
Native Intel testing or an explicit new waiver, signing/notarization, signed
installation/update/rollback/removal and publication remain gated. The installed
unsigned bundle does not qualify a future signed distribution.

## Signed 0.2.0/build 25 release — 2026-10-18

The owner authorized signing, Apple notarization and publication and explicitly
waived native Intel testing for engine 0.2.1 and companion 0.2.0/build 25.
Both signed distributions pass their final installation/lifecycle checks.
Actual signed UI Apply/Undo/Redo on Glyphs 4.2/build 4202 preserves the exact
reference, node structure, widths and live hint metadata/attachments. Rollback
to published signed build 15, removal and reinstallation pass. The shared engine
is unchanged. Earlier unsigned statuses and failed trials above are historical.
See the [final release record](../../docs/RELEASE_0.2.1.md) and
[public qualification receipt](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.0/qualification.json).
Native Intel remains untested, owner-waived; native HOI on 4202 remains unqualified.

## Universal 0.2.1/build 26 published — 2026-10-20

The signed, Apple-notarized release consumes engine 0.2.2 and the shared v1 engine-settings
contract, retaining earlier accepted engine versions. It persists explicit
choices, honors user overrides before managed choices and never replaces an
executable during engine selection. Existing releases remain immutable.

The owner removed native Intel qualification as a blocker until an Intel machine
is available. Native Intel remains untested, owner-waived; arm64, Rosetta and
universal inspection remain required. Other release gates still apply.
See [qualification](../../docs/RELEASE_0.2.2.md).

## Universal 0.2.2/build 27 — 2026-10-20

The owner requested final universal release and GitHub publication of the sidebar
focus-ring spacing fix. Eight-point horizontal insets and viewport-aware row
widths preserve the selected field border with overlay and legacy scrollbars.
The separately released engine remains 0.2.2, unchanged. Build 27 invalidates the
native Python cache. Local AppKit checks cover all four modes and sixteen
basic/expanded/scroller layouts. Final signing, notarization and installed
qualification are recorded in the release manifest and public qualification receipt.
Native Intel remains untested and owner-waived until hardware is available.
