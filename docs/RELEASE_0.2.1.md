# Beztrace 0.2.1 and companion 0.2.0 release preparation

The owner requested a final companion 0.2.0 on 2026-10-17 and selected engine
0.2.1 after verification of the existing published 0.2.0 engine. The source engine
is 0.2.1; the companion is 0.2.0/build 24. This prepares local
unsigned artifacts; it does not claim stable distribution qualification.
Published engines 0.2.0 and 0.1.1, the 0.2.0-dev.1 preview and companion releases retain
their original tags and bytes.

The published standalone [0.2.0 release](https://github.com/thierryc/beztrace/releases/tag/v0.2.0)
was verified read-only: tag `0344b8d6c1935b9de3009cbd46257bfa99060b8a`,
signed/notarized ZIP SHA-256
`07b00b1cf16c24f4bdcce55f3f0c351a291e24ae1b9d2704c3b705f323d6fff7`
and PKG SHA-256
`48a1dbebb4ddb6d05c56fc2a856a0b278db378359859c84ccaf2508fc8618259`.
Its release receipts are historical evidence, not qualification for 0.2.1.

## Included work

- Standalone vector, image-to-reference and joint-image master matching, paired
  comparison, bounded point growth and explicit correspondence.
- Independently verified Levien-first fitting with the refined least-squares
  fallback. Efficient joint smoothing keeps the original-source error budget,
  reference, on-curves, node types, flags, order and counts. Production graph
  selection remains deferred.
- The four-mode Glyphs companion has small contextual sidebar groups, conditional
  manual correspondence/growth/native HOI controls, hint-preserving application,
  stale-result protection and validated import/export.
- JSON schema v1 and path data v2 remain unchanged. Companion build 24 explicitly
  accepts engine 0.2.1 and retains support for previously accepted versions.

The promotion changes version identity, compatibility and release documentation;
it does not change the accepted fitting, smoothing or UI layout algorithms.

## Local reproduction

Use fresh output directories and the existing local toolchain. These commands
never install, sign, notarize or publish:

```sh
python3 scripts/build_development_engine.py --output .build/beztrace-0.2.1
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.2.0-build24-final
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-0.2.0-build24-final
BEZTRACE_ASAN_DEVELOPER_DIRECTORY=/Applications/Xcode-beta.app/Contents/Developer \
  bash scripts/check_local.sh .build/final-0.2.1-local-checks
```

The engine remains a separate runtime prerequisite. A packaged companion outside
this checkout uses the system engine unless an explicit executable is selected;
the verified hybrid fitting and match-smoothing capabilities must be available for paired workflows. Selecting a
local engine never replaces the system executable. Source-checkout selection uses
`.build/beztrace-0.2.1/bin/beztrace`.

## Qualification and authorization still required

The [quality gates](QUALITY_GATES.md) and [native acceptance checklist](../Companions/Glyphs/NATIVE_TESTING.md)
remain release blockers. Earlier fake-host AppKit checks and prior published
release receipts do not qualify these exact engine/companion artifacts.

- Freeze and review the exact source revision, reconcile the branch with the
  remote, and reproduce from a clean checkout. Preserve all existing worktree
  changes until their ownership and inclusion are reviewed.
- Complete installed/loaded Glyphs selection, preview, Apply, hint preservation,
  Undo/Redo, save/reopen/export, standalone import and compiled variable-font
  acceptance on disposable fixtures for the exact build. No user fonts may be
  substituted for disposable qualification fixtures.
- Complete matching resource/performance and native architecture requirements.
  Rosetta evidence remains distinct from native Intel execution; the historical
  companion build-15 Intel waiver is not a new architecture waiver.
- Run the sanitizer with the documented installed Xcode beta toolchain. Retain
  earlier stable-toolchain platform-policy failures separately; do not skip the gate.
- Obtain the required authorization for source commit/freeze, installation,
  relaunch, Developer ID signing, Apple notarization and uploads/publication.
  Prior 0.1.x authorizations do not grant these operations for the new engine and companion releases.
- Sign and notarize the exact engine/installer and companion artifacts, qualify
  installation/rollback/removal and the non-Glyphs packaged workflow, then verify
  final manifests, SBOMs and anonymous download checksums before publication.

The [engine release procedure](RELEASE.md) refuses a dirty final source checkout.
The [companion procedure](../Companions/Glyphs/RELEASE.md) retains independent
versioning and qualification. No installer or final tag is produced by the local
unsigned preparation. Keep stable download links on the existing published
release until the new distributions pass their own gates.
