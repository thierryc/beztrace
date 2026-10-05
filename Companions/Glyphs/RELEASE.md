# Companion release procedure

The current implementation produces unsigned development packages only. It is
not covered by the engine's earlier publication/signing authorization.

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
   Silicon and Intel loading, and UI accessibility. Freeze the source revision,
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
