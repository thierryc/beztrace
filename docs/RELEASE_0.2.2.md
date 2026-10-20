# Universal engine 0.2.2 and companion 0.2.1/build 26

Published 2026-10-20. Status: signed, Apple-notarized and qualified.
Frozen source: `64c9c47456b0bd671f1e129f75dbc9da8b602a6f`.
Source branch: `lit/release-v0.2.2`. Published engine 0.2.1 and companion
0.2.0/build 25 retain their tags and every distributed byte.

Both new distributions target macOS 13+ and contain arm64 and x86_64 slices.
This deployment target is distinct from tested OS coverage. The owner's
2026-10-20 instruction removes native Intel qualification as a release blocker
until an Intel Mac is available. Native Intel is untested, owner-waived;
Rosetta execution is separate evidence. All other release gates remain required.

## Changes

Engine 0.2.2 changes version identity only. Tracing, matching, fitting, smoothing,
JSON schema v1 and path-data version 2 are unchanged. Companion 0.2.1/build 26
accepts 0.2.2 and implements the documented shared `engine-settings-v1` contract.
It prefers explicit user selection over managed selection and defaults. Choose
Engine persists the user's path while preserving managed and unknown settings.
Malformed, oversized, symlinked and concurrently changed configuration is
refused. Engine selection never writes or replaces executables or plugins.

The Glyphs MCP managed installer and its catalog remain separate. Its Apple
Silicon/macOS 26.6.2 support limit does not change merely by publishing these
Beztrace distributions. Consumers must qualify their integration independently
and must preserve independent or modified installations.

## Qualification

All 27 local source commands pass, including 194 Swift tests per architecture
(two intentional skips each), Address Sanitizer and 188 companion tests. All 18
pair cases are byte-identical on native arm64 and x86_64 under Rosetta. The 12
controlled signed smoothing cases preserve prior geometry, reports and refusals.
Both unsigned companion packages reproduce byte-for-byte.

The signed engine passes installation, packaged JSON/SVG and three pair workflows,
rollback to 0.2.1, owned removal and reinstallation in a macOS 14.6.1 arm64 VM.
Gatekeeper remains enabled. Developer ID signatures, Apple notarization logs,
installer signature and stapled ticket validate. Install assessments accept the
CLI and companion as Notarized Developer ID. An app-style execute assessment is
not used as a CLI acceptance criterion; a separate codesign `=notarized` requirement
probe did not pass, while the Apple logs and install assessments did.

Five fixtures, three warmups and 30 samples pass all resource gates: worst process
p95 794.6 ms and peak RSS 30 MB, with core median/p95 below 1.5 times the pinned
Rust baseline. An earlier run while the VM was active exceeded the timing gate;
it is retained locally and excluded from the quiescent qualification result.

Signed installed build 26 passes native Apply/Undo/Redo, exact reference,
on-curve/node structure, width and live hint preservation on Glyphs 4.2/build 4202,
official Python 3.14.6, macOS 26.7.1 arm64. Choose Engine persists through panel
reopen, app relaunch and reinstall. Rollback to published build 25, removal
(menu/module absence) and build 26 reinstallation pass; the host shared engine
stays unchanged. Temporary test selection and the task macro were archived after
testing. The user closed the unrelated font before further lifecycle relaunches.

Exact applied coordinates restored into a detached disposable font pass fresh
save/reopen and variable TTF export. Maximum native storage deviation is 0.000425
units. The exported TTF passes 201 interpolation positions with compatible topology
and maximum compiled interpolation rounding 0.003663 units. A signed standalone
packet imports into a detached native recipient and round-trips with exact geometry
and explicit axis confirmation. This is bounded interpolation evidence, not a
shaping audit. Glyphs omits custom hint userData on save as in the untouched prior
control; live Apply/Undo/Redo preserves it. Native HOI remains disabled and
unqualified on build 4202.

All 67 engine production Swift files are unchanged from 0.2.1 except version
identity. Native geometry, image IO, staging, hints, recovery, HOI and neutral
exchange modules are byte-identical to build 25. Earlier broader native four-mode,
recovery, copy-cost and robustness receipts remain historical, with source binding;
they are not relabeled as fresh tests.

## Published artifacts

- [Engine 0.2.2](https://github.com/thierryc/beztrace/releases/tag/v0.2.2):
  [manifest](https://github.com/thierryc/beztrace/releases/download/v0.2.2/release-manifest.json),
  [qualification](https://github.com/thierryc/beztrace/releases/download/v0.2.2/qualification.json).
- [Companion 0.2.1/build 26](https://github.com/thierryc/beztrace/releases/tag/glyphs-v0.2.1):
  [manifest](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.1/companion-manifest.json),
  [qualification](https://github.com/thierryc/beztrace/releases/download/glyphs-v0.2.1/qualification.json).

| Artifact | SHA-256 |
| --- | --- |
| Engine universal ZIP | `d606d95a70afb17496ce136056a8677a23e7d0f36bfed20c9803d2a455d91c14` |
| Engine stapled PKG | `085ff3ac1906a5fc154bdd247573bf673fcbc2dae2dbfcce2605c7a85a0f092c` |
| Companion signed ZIP | `e2db31b3387bac806ba4d43de83c43004b3e01da2da3a5a07a46c27feed1cebf` |

All 17 new assets were downloaded anonymously and match local bytes and GitHub
SHA-256 digests. All 70 prior assets, nine prior tags and nine prior release records
retain their IDs, timestamps, digests and contents. GitHub Actions remains disabled.
Local evidence: `.build/release-0.2.2-review/` in the release worktree; public
receipts contain summaries and hashes without user font data.
