# Glyphs MCP v2 integration handoff — Beztrace 0.1.1

**Published stable release, verified 2026-10-05.** [Release page](https://github.com/thierryc/beztrace/releases/tag/v0.1.1) · [Public API](https://api.github.com/repos/thierryc/beztrace/releases/tags/v0.1.1). Both return HTTP 200. All six assets download anonymously and match SHA256SUMS, release-note hashes and GitHub asset digests. `draft=false`, `prerelease=false`; the tag resolves to `9737f21fabfda0dc9e6728bd34df2f83380238e9`.

Engine distribution blockers: **none**. Companion native/distribution blockers remain separate below.

PR #10 merged the installer/test follow-up into main as `2c6c511888bce4d6b56282590f3228b154b0d07f`. The immutable release tag points to the exact qualified branch commit below; this merge adds no different release payload.

Signed annotated tag object: `b2c5aed32ebdc074140e3f76af74e386e02594dd`; local GPG verification reports a good EDDSA signature by Thierry Charbonnel, key `1F7704C2E61C10698BC5BF3D850806FAD8A2793A`. The tag resolves to source commit `9737f21fabfda0dc9e6728bd34df2f83380238e9`.

## Source and contracts

Exact `v0.1.1` tag/source commit: `9737f21fabfda0dc9e6728bd34df2f83380238e9`. Historical qualified source: `7e43a0b48fec0634e9393f9f33d2d5cc260ced39`. PR #9 merged as `1c89f50538cff2351cdb2e4558d1f1e3e7292ceb`. Engine production source and schemas are identical across these revisions. The final candidate adds installer branding and corrects the CLI test harness to select its own build instead of a preserved dev.4 executable.

Production source fingerprint: `8c6c106de0de453b317edc1c5c4d35ec38ec2f188188d44ff154faf7f7b06aea`. Signed executable SHA-256: `3695e8fa41e941a21003052add1b65aea758fb8cd72addfd037288a94265e0cf`.

The stable engine retains the small-contour area/closed-fit correction, safe handle rounding, topology-safe Grid fallback, and protected small convex curves from dev.1–dev.4. It additionally includes the source-only minimum-node cleanup that was absent from the older dev.4 archive. This is a tracing correction release, beyond an engine-version replacement.

JSON schema version **1**, path-data version **2**, engine **0.1.1**, preserved Y-up neutral JSON, unchanged public Swift options/API. Consumers must validate the engine and both contract versions and use the emitted complete paths and deterministic warnings.

Minimum-node cleanup runs after redundant-point removal and before optional Grid. A finite, closed, nondegenerate two-segment loop splits the longest control polygon at t=0.5 by exact De Casteljau subdivision; ties choose the first segment. Geometry and signed area are unchanged before later cleanup. Three-node and larger contours are unchanged. Invalid empty, one-segment and degenerate contours still fail; the final validator requires at least three on-curves.

Tests: `SmallContourTests.testTwoCubicLoopGainsAnOnCurveWithoutChangingGeometry` checks exact subdivision, 101 samples at 1e-9 tolerance, signed area, validator rejection before repair, acceptance after repair, and counter winding. `testMinimumOnCurveRepairLeavesThreeAndLargerContoursUnchanged`, `testCollapsedLinesRemainInvalid`, and `testSmallConvexOvalsRemainCurvesAcrossPresets` cover preservation, invalid input and preset output. The complete frozen corpus also has at least three on-curves per contour.

The frozen source-tag documentation and embedded root README capture prepublication status. The current release guide and this handoff record the subsequently verified publication; no tag or distributed bytes are rewritten.

## Download inventory

| Asset | Direct URL | SHA-256 |
| --- | --- | --- |
| beztrace-0.1.1-macos-universal.zip | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/beztrace-0.1.1-macos-universal.zip) | `75546a8530e0bf6f2ef4a849b298312522f21a4c6cf4c5a706c2f1448a4b8682` |
| beztrace-0.1.1.pkg | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/beztrace-0.1.1.pkg) | `560d72540ab1013c444105ac45abea1780229145de4e174e7cfd0072d9a81975` |
| beztrace-0.1.1-source.spdx.json | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/beztrace-0.1.1-source.spdx.json) | `a89ef12ba5040affec821905a7aa1e812783271af3adb8528e241b3bb0272a5e` |
| beztrace-0.1.1-binary.spdx.json | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/beztrace-0.1.1-binary.spdx.json) | `11060d00031c34a1fbc7d2f636615698c43ae804b4413f1075198cfe46202a31` |
| release-manifest.json | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/release-manifest.json) | `7a189d1c6a79fe8cb2bcec3473a865b215cd736e55fdb46d2cdd9ee9371d6a3e` |
| SHA256SUMS | [Download](https://github.com/thierryc/beztrace/releases/download/v0.1.1/SHA256SUMS) | `b28b7c271c95accf3d07cb0edca38ca17ef1775737bde850745738178411fbf5` |

[Apache-2.0 license](https://github.com/thierryc/beztrace/blob/v0.1.1/LICENSE-APACHE), [MIT license](https://github.com/thierryc/beztrace/blob/v0.1.1/LICENSE-MIT), and [third-party notices](https://github.com/thierryc/beztrace/blob/v0.1.1/THIRD_PARTY_NOTICES) are also available at the exact source tag. Licenses and notices are inside the ZIP at `beztrace/share/LICENSE-APACHE`, `LICENSE-MIT`, and `THIRD_PARTY_NOTICES`; installer locations are `/Library/Application Support/beztrace/share/`. Both archives include `trace-result-v1.schema.json` and SPDX source/binary SBOMs. The versioned SBOMs and release manifest are also separate assets. SPDX 2.3 source and binary inventories preserve the derivative img2bez baseline `23073ca08ecdac61ad0e838bfae49a590bc2c7cc` and Apple-system-only runtime dependencies.

## Qualification evidence

All 27 clean-source qualification commands pass at `9737f21fabfda0dc9e6728bd34df2f83380238e9`. Both arm64 and x86_64/Rosetta execute 100 optimized Swift tests with one intentional maintenance skip and zero failures. All six native GitHub CI jobs pass. All 100 immutable corpus traces reproduce the accepted paths, bounds, statistics and warnings; the original human acceptance is reused unchanged. JSON is byte-identical across architectures. The 50,000-case AddressSanitizer fuzz evidence is reused with an explicit unchanged core/harness source proof. The 107 companion contracts and isolated fake-host AppKit check pass with the final engine. Relative performance, CLI latency and memory gates pass: process p95 349.070–763.480 ms; maximum RSS 28.422 MiB, with three warmups and 30 measurements per fixture and engine.

[Native CI](https://github.com/thierryc/beztrace/actions/runs/37322512226). Full local logs and artifacts are preserved under `.build/release-v0.1.1-branded`; the original candidate and failed stale-artifact test investigation remain under `.build/release-v0.1.1-handoff`. [Machine-readable handoff](release-evidence-v0.1.1.json).

## Distribution evidence

Universal executable: **arm64 + x86_64**; each Mach-O slice reports **LC_BUILD_VERSION minos 13.0, SDK 26.2**. Both return `beztrace 0.1.1`. Developer ID Application and Installer: **Thierry Charbonnel (N9U29A4T8J)**, with trusted timestamps and hardened runtime for the executable.

Apple accepted ZIP submission `141a2161-d343-47a2-99be-faf7246555f0` and PKG submission `0810249c-3565-43d3-881a-16a47413f679`, with no issues. Apple's submitted PKG hash was `d0f079e164e5161d155da8a681b5cb7b58f15c847bba92ac9fb2fee4de42ea05`; stapling adds its ticket and produces the final published PKG hash in the inventory above. PKG stapling and validation pass; installer Gatekeeper assessment reports `Notarized Developer ID`. Both executable slices satisfy `codesign --verify --all-architectures --strict -R=notarized --check-notarization`. ZIP/standalone CLI tickets cannot be stapled; use the stapled PKG for an offline carrier. A raw CLI is not an app, so `spctl --type execute` is not the appropriate app assessment for it. [Apple workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

The exact branded PKG was installed by the owner with administrator authentication. Receipt `dev.beztrace.cli` version 0.1.1, installed hash equality, universal slices, signatures, Apple trust, stapling, Gatekeeper, and standalone JSON/SVG output pass. The product title, welcome and completion name **Beztrace 0.1.1**; the real-PKG metadata regression test checks packaged resources. No Keychain, administrator, or Apple upload permission remains missing.

Performance qualification retains the initial failed run: generated-S process p95 1316.360 ms exceeded the one-second gate during substantial observed background CPU activity. That run is not accepted or discarded. The final evaluator uses the documented controlled repeat; all measurements and the initial rejection remain in local evidence.

## Separate Glyphs companion

Source and newly verified local package: **0.1.0 build 12**, unsigned, not notarized, not published, manifest `development-unqualified`, `nativeTestedBuilds: []`. ZIP SHA-256 `6341e27f50a180b6b6258a19029942181d3c974c3a55c6c367097744db41212f`, stored under `.build/release-v0.1.1-handoff/companion-build12`. Manifest, SHA256SUMS, SPDX SBOM and GlyphsSDK license/provenance accompany that local package. The loader is universal; macOS 13+, Glyphs 4.1 build 4107+ within Glyphs 4, and host Python 3.9+/PyObjC/AppKit/Foundation/Quartz are required.

Build 12 accepts engine 0.1.0, 0.1.1-dev.1–dev.4, and 0.1.1 with JSON schema 1/path-data 2, and requires executable/JSON version agreement. Select the installed stable engine explicitly when corrected minimum-node output is required; a checkout may still prefer its preserved dev.4 engine.

Installed payload is **0.1.0 build 11** at `~/Library/Application Support/Glyphs 4/Plugins/Beztrace.glyphsPlugin`, linking to `.build/glyphs-companion-0.1.0-build11/Beztrace.glyphsPlugin`. Its contract excludes stable 0.1.1. The loaded build was not established in this task. No companion installation, Glyphs relaunch, font edit, signing or publication was performed.

For a separately authorized upgrade, place the verified `Beztrace.glyphsPlugin` in the actual Glyphs 4 Application Support `Plugins` directory, relaunch Glyphs, verify About reports build 12, and choose `/Library/Application Support/beztrace/bin/beztrace`. These are instructions, not completed actions. See the companion README, release procedure and native testing checklist.

Missing native qualification for exact build 12: authorized install/relaunch and loaded-build confirmation; native menu and UI layout/accessibility/keyboard/light-dark review; preset/manual-input/persistence/reset behavior; real PNG/JPEG import and image Undo/Redo; visible alignment at multiple zooms with crop, DPI/EXIF, scale, skew, reflection and rotation; foreground/background insertion with existing content/image/width preservation and exact Undo/Redo; captured-target navigation, stale content/image/placement/file rejection; Cancel, closure, timeouts, duplicate/late results, wrong-engine and invalid-input recovery; explicit-layer placement API conflicts, whole-batch preflight and recovery; fresh-host runtime setup and Apple Silicon/Intel loading; installation/update/rollback/removal; separate signing/notarization/Gatekeeper and publication authorization. Historical detached native backend probes are evidence for their tested earlier revisions, not visible build-12 acceptance.

The 107 contract tests and isolated AppKit smoke check use the final engine and pass; AppKit uses fake font objects. These do not qualify native Glyphs UI. The engine release does not qualify or distribute this plugin, and Glyphs MCP does not need this native companion to consume the neutral engine contract. The Glyphs MCP repository and runtime were untouched.
