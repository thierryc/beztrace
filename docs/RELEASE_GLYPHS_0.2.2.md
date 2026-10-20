# Universal companion 0.2.2/build 27

Published 2026-10-20 at [glyphs-v0.2.2](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.2.2).
Frozen source: `3294e200d18c502b4d3b36d1ec48e3a6809ea1e4`.
Engine [0.2.2](RELEASE_0.2.2.md) is unchanged and remains separately distributed.

The settings sidebar adds eight-point horizontal insets and fits controls to the
available scroll viewport. The selected field's native focus border stays fully
visible with overlay or legacy scrollbars. This changes layout and About identity;
geometry, neutral contracts, engine selection, transport and font-editing behavior
are unchanged. Build 27 gives Glyphs a new Python cache timestamp.

## Qualification

- All local checks pass: 27 source commands, 194 Swift tests per architecture
  (two intentional skips), Address Sanitizer, 188 companion tests, universal
  packaging and 18 byte-identical arm64/Rosetta pair cases.
- Two unsigned universal archives reproduce exactly. The signed archive has both
  loader slices, complete licenses/notices, matching schemas and SPDX SBOM.
- Developer ID signatures validate. Apple notarization submission
  `e5a60738-d7c6-47a3-ab7d-d5ca6e96d741` is Accepted, and Gatekeeper's install
  assessment accepts the exact signed bundle as Notarized Developer ID.
- The installed signed payload matches the manifest. Native Glyphs 4.2/build 4202,
  official Python 3.14.6, macOS 26.7.1 arm64 verifies the complete focused border,
  overlay/legacy layouts, explicit UI Apply and uninterrupted Undo/Redo. Reference,
  on-curves, node structure, widths and live hints remain exact. Fresh save/reopen
  preserves supported geometry and hint attachments, with maximum coordinate
  storage deviation 0.000425 units.
- Rollback to exact published build 26, native dialog loading, owned removal,
  absent menu/module, build 27 reinstall and native dialog loading pass. No user
  fonts were open before relaunch. The disposable fixture was preserved and closed;
  the task macro was archived. The host shared engine and settings are unchanged.
- Isolated AppKit checks pass all four modes (23 checks) and sixteen combinations
  of mode, basic/expanded settings and scrollbar style. The padding implementation
  matches the previously verified source. Broader native/engine performance,
  variable export and neutral exchange receipts remain historical, bound to the
  byte-identical geometry and transport modules; they are not relabeled as reruns.

A harness checked font count before asynchronous close completed; a separate
native event-loop check confirmed zero. Apply/Undo/Redo and save/reopen assertions
had already passed. This excluded cleanup timing assertion did not modify the
plugin or relax any preservation requirement.

## Distribution

Signed universal ZIP SHA-256:
`376b7a2f424f12d5d6b015712085f18d9836b5e84510c5e3b72e82bf702fae1c`.

[Manifest](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.2/companion-manifest.json),
[qualification receipt](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.2/qualification.json),
[all asset checksums](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.2/release-assets-SHA256SUMS).
All eight new assets download anonymously with exact SHA-256 matches. All earlier
release records, tags and asset IDs/digests/timestamps are preserved.

Native Intel remains untested and owner-waived until hardware is available.
Rosetta is separate evidence. macOS 13 is the deployment target, not a claim of
running every OS release. Native HOI remains disabled and unqualified on build
4202. Glyphs omits custom hint userData on file save; live Apply/Undo/Redo preserves
it. Glyphs MCP managed installer/catalog qualification remains separate and
independent or modified installations must not be overwritten automatically.
GitHub Actions remains disabled; only locally verified static output is deployed
to the existing `gh-pages` branch under the Pages-only exception.
