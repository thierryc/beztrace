# Beztrace 0.2.1 and companion 0.2.0 release qualification

The owner requested a final companion 0.2.0 on 2026-10-17 and selected engine
0.2.1 after verification of the existing published 0.2.0 engine. The source engine
is 0.2.1; the companion is 0.2.0/build 25. Both signed universal distributions were released on 2026-10-18 after the
qualification recorded below. Earlier unsigned packages remain historical evidence.
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
- JSON schema v1 and path data v2 remain unchanged. Companion build 25 explicitly
  accepts engine 0.2.1 and retains support for previously accepted versions.

The promotion changes version identity, compatibility and release documentation;
it does not change the accepted fitting, smoothing or UI layout algorithms.

## Local reproduction

Use fresh output directories and the existing local toolchain. These commands
never install, sign, notarize or publish:

```sh
python3 scripts/build_development_engine.py --output .build/beztrace-0.2.1
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-0.2.0-build25-ready
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-0.2.0-build25-ready
BEZTRACE_ASAN_DEVELOPER_DIRECTORY=/Applications/Xcode-beta.app/Contents/Developer \
  bash scripts/check_local.sh .build/final-0.2.1-local-checks
```

The engine remains a separate runtime prerequisite. A packaged companion outside
this checkout uses the system engine unless an explicit executable is selected;
the verified hybrid fitting and match-smoothing capabilities must be available for paired workflows. Selecting a
local engine never replaces the system executable. Source-checkout selection uses
`.build/beztrace-0.2.1/bin/beztrace`.

## Qualification completed on 2026-10-17

The release source is frozen at
`217dcc0aad50a4c4a6b7e8c65e6bacc0931e2054` in a clean isolated checkout,
reconciled with the published 0.2.0 source. Build 25 supersedes build 24 after
correcting native getter-backed hint metadata and preserving custom hint data
omitted by Glyphs' native copy operation. Earlier artifacts and failed trials
are retained separately.

| Check | Exact candidate result |
| --- | --- |
| Local source matrix | All 27 commands pass; 194 Swift tests per architecture, two intentional skips each; 180 companion tests; AddressSanitizer passes using the installed Xcode beta toolchain |
| Architecture comparison | Universal slices verified; 18 R/Y pair jobs and 12 smoothing jobs produce identical native arm64/Rosetta output; native Intel untested |
| Same smoothing benchmark | All 12 cases retain accepted outlines, complete reports, source-error bounds and refusal thresholds |
| Reproducible unsigned archives | Both engine and companion ZIPs are byte-identical across two independent packages |
| Standalone extracted package | Three matching workflows pass; neutral output imports and round-trips in a disposable native recipient |
| Installed companion | All four UI modes, exact preview/application readback, reference/node/hint preservation, native UI Undo/Redo, injected-failure recovery, cancellation and stale-source guards pass |
| Fresh-file exchange | Geometry and supported hint attachments/settings survive save/reopen; Glyphs omits custom hint userData on both matched and untouched control glyphs |
| Compiled interpolation | Native variable TTF export; 201 positions for each of three workflows, 603 compatible checks; maximum interpolation coordinate rounding 0.003692 units |
| Tracing performance | Five fixtures, three warmups and 30 samples: worst process p95 759 ms and peak RSS approximately 30 MB |

Native acceptance uses disposable fonts on Apple M1 Max, macOS 26.7.1,
Glyphs 4.2/build 4202 and the official Glyphs Python 3.14. No user font was
modified. The unsigned companion is installed and loaded; qualification explicitly
selected the local 0.2.1 engine and retained the existing system engine.

The controlled 12-node smoothing case changes two target handles and certifies
0.790079 units within its original 1-unit limit. The R raster pair refuses a
non-collinear fixed-reference smooth join when smoothing is enabled; disabling
that optional step succeeds at the same fitting tolerance. Refusal keeps Apply
disabled. Native HOI remains gated to build 4108 and was not qualified on 4202.
These bounded samples do not establish arbitrary-font or shaping coverage.

See [companion build 25 qualification](../Companions/Glyphs/QUALIFICATION_BUILD25.md)
for native scope and limitations. The local review packet is
`.build/release-0.2.1-companion-0.2.0-build25/REVIEW.md`; its manifest, checksums
and `qualification/summary.json` bind the source and evidence. It is not a public
download or a signed release manifest.

| Unsigned local archive | SHA-256 |
| --- | --- |
| `beztrace-0.2.1-macos-universal.zip` | `ee85618d363da312723378e6fdefced3f6fd0409af0c1c725a825e342670e7f4` |
| `beztrace-glyphs-0.2.0-build25-macos-universal.zip` | `407a1cf3738367c74201c6ae23db965c38fa59cca9e5c0143264ad73ae6e8fbd` |

## Signed distribution preparation — 2026-10-18

The owner explicitly waived native Intel testing for engine 0.2.1 and companion
0.2.0/build 25 and authorized existing Developer ID/Apple credentials, signed
installation qualification and publication after all remaining checks pass.
Native Intel remains **untested, owner-waived**; Rosetta remains separate evidence.

The frozen source remains `217dcc0aad50a4c4a6b7e8c65e6bacc0931e2054`.
Separate staging copies are Developer ID signed. Apple accepted the engine ZIP,
engine PKG and companion ZIP; the PKG ticket is stapled and validated, and its
Gatekeeper assessment reports Notarized Developer ID. The companion's only
payload changes from the verified unsigned package are signing bytes, the code
resource seal and the signed-loader SBOM. Python sources remain unchanged.

The extracted signed engine passes standalone JSON/SVG tracing, all 18 native /
Rosetta pair cases, and the same 12 smoothing cases with exact geometry, reports,
bounds and refusal thresholds. A settled five-fixture, 30-sample performance
repeat passes at 746 ms worst process p95 and 29.5 MB peak RSS. The earlier
over-limit run overlapping VM startup is retained separately.

The signed installer passes its full lifecycle in the owned macOS 14.6.1 arm64
VM: install, rollback to published 0.2.0, owned removal and reinstall. Exact
binary hashes, installed JSON/SVG and two pair workflows, signatures, stapling
and Gatekeeper checks pass. The host shared engine remains untouched.

The signed companion passes actual native UI Apply/Undo/Redo on Glyphs
4.2/build 4202. Undo restores the exact original semantic state; Redo restores
the exact benchmark result. Reference geometry, on-curves, node structure,
widths, hint settings, attachments and custom userData are preserved. Only two
target handles change in the controlled 12-node, 1-unit sample. Native rollback
to published signed build 15, removal and signed build 25 reinstallation pass;
the final signed payload matches the manifest. No user font was modified.

Test-setup failures and raw hint-cache observer mismatches are retained as
excluded trials. The successful isolated UI cycle has no intervening font
scripts between Apply, Undo and Redo. All disposable test fonts were saved and
closed before lifecycle relaunches.

Local signed receipts and progress are in
`.build/signed-release-0.2.1-20261018/`; the earlier unsigned review packet remains
immutable historical evidence. Signing alone does not qualify publication.

## Published distributions

[Engine 0.2.1](https://github.com/thierryc/beztrace/releases/tag/v0.2.1) and
[companion 0.2.0/build 25](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.2.0)
retain independent manifests, SPDX inventories, checksums and qualification
receipts. Source-tag and bundled documents retain their preparation-time status;
the external release receipts record final qualification.

| Signed artifact | SHA-256 |
| --- | --- |
| Engine universal ZIP | `d4514513aa0da6b39991234fc9caeb9c0bf717dc8b3bcc0c9fd08c87df2b7776` |
| Engine stapled PKG | `5598783cd342c169ca48d52468164a5d8cf2bfdd48e3a0cc2225f59ccfaadc2b` |
| Companion universal ZIP | `275f07b88114dbb0c6b889d3ec8f4feffc9d788be00ded16127f3d09e458448f` |

[Engine qualification](https://github.com/thierryc/beztrace/releases/download/v0.2.1/qualification.json)
and [companion qualification](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.0/qualification.json)
state bounded coverage and the explicit native Intel waiver. ZIPs have no
stapled ticket; the engine PKG does. Published older releases stay unchanged.
