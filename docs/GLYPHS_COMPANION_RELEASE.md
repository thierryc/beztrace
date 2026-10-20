# Beztrace for Glyphs independent release

[Current release: 0.2.1/build 26](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.2.1),
published 2026-10-20, is a separately signed/notarized universal companion for
engine 0.2.2. Source is frozen at `64c9c47`. Native Apple Silicon qualification
covers Glyphs 4.2/build 4202, signed Apply/Undo/Redo and update/rollback/removal/
reinstallation. Native Intel is untested and explicitly owner-waived for these
versions. See the [full release record](RELEASE_0.2.2.md),
[manifest](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.1/companion-manifest.json)
and [qualification](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.1/qualification.json).

Install engine 0.2.2 separately, then open the companion bundle in Glyphs and
relaunch. Installing/removing the companion leaves the shared engine untouched.
The prior signed 0.1.0/build 15 release below retains its original tag and bytes.

Choose Engine now persists explicit selections while preserving managed and unknown settings.
Native Intel qualification is deferred until hardware is available; all other gates remain required.

## Historical 0.1.0/build 15 release

[Official release: 0.1.0/build 15](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.1.0),
published 2026-10-05 under independent tag `glyphs-v0.1.0`. The repository's
latest stable engine remains 0.1.1.

The source payload is frozen at
[dbd7a696afda9a215c8e8a4aa42315cd799116f9](https://github.com/thierryc/beztrace/tree/dbd7a696afda9a215c8e8a4aa42315cd799116f9/Companions/Glyphs).
This documentation update follows qualification and does not change those
distributed bytes or the frozen source tag. Bundled/source-tag documents retain
preparation and historical statuses; final qualification is recorded in the
external release manifest and report. The source builder still produces unsigned
development-unqualified artifacts.

| Item | Value |
| --- | --- |
| Archive | `beztrace-glyphs-0.1.0-build15-signed-macos-universal.zip` |
| ZIP SHA-256 | `8df74372d7c003802067f4b6ac64b5fcd4fb8c489b8b121016c816798cc0dcad` |
| Signed inventory SHA-256 | `1e58eaee77a73311bb1dc6b486fe0790ad18c97487d95435b150ededa22dff5a` |
| Developer ID team | `N9U29A4T8J` |
| Apple accepted submission | `66043b20-bb3a-40b9-bce2-ebcb790d93eb` |
| Native scope | macOS 14.6.1 arm64; Glyphs 4.1.1/build 4108 trial; official Python 3.14.6 |
| Intel execution | Untested, explicitly owner-waived because no recent Intel Mac is available |

The companion passes 114 tests with real stable-engine corpus integration,
package/product-boundary verifiers, native controller safety and live settings,
invalid values, cancellation, target switching, stale rejection, recovery
failures, image/path placement, foreground/background first Trace, zero-width
Done/Undo/Redo, crop/affine/DPI/EXIF/alpha alignment, UI and install/update/rollback/
remove/reinstall checks. See the release's `qualification-build15.md` for
per-check scopes and evidence. Signature and notarization were verified against
the exact signed package on a Gatekeeper-enabled host; ZIP has no stapled ticket.
No offline-stapled distribution or native Intel result is claimed.

[Manifest](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.1.0/companion-manifest.json),
[package checksums](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.1.0/SHA256SUMS),
[all asset checksums](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.1.0/release-assets-SHA256SUMS),
and [qualification report](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.1.0/qualification-build15.md)
are independent companion assets. The external signed SPDX inventory includes
post-signing loader checksums; the embedded unsigned-source inventory retains
its original provenance.

Stable engine 0.1.1 is an external prerequisite; its executable checksum remains
`3695e8fa41e941a21003052add1b65aea758fb8cd72addfd037288a94265e0cf`.
No stable engine tag/asset, public MCP API or dependency changed. Engine signing
and notarization do not qualify this plugin. No automatic plugin installer is
provided, and no Glyphs MCP repository edits are part of this release.

Publication verification passed: the tag resolves to the frozen source, all eight
anonymous public asset downloads match their local SHA-256 checksums, and stable
engine release metadata, asset IDs/checksums/sizes/timestamps and tag are unchanged.
