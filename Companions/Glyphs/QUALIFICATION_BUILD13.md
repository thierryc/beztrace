# Build 13 independent qualification record

Recorded 2026-10-05. Companion 0.1.0/build 13 is **development-unqualified,
unsigned, unnotarized and unpublished**. Stable engine 0.1.1 is a separate,
unchanged prerequisite; its signing/notarization does not qualify the plugin.

## Source and review

Prepared worktree: `/private/tmp/beztrace-companion-first-trace`.
Branch: `lit/glyphs-companion`; base revision:
`b1f8fa4198e27fec9208c1967fd79355dde5e9f0`. The owner authorized the local build-13 source, regression-test and
documentation commit on 2026-10-05. The clean package manifest records the
resulting exact source revision. Push, signing and publication remain separate.

Reviewed fixes load `GSBackgroundImage.image` before capturing image properties,
retaining explicit crops and genuine stale-image protections. Build 13 reserves
ZIP timestamp `2026-09-27 00:00:26` to invalidate equal-size timestamp-based
Python caches. Python changes require a new build. Existing regression tests
cover lazy crop initialization, explicit crop, external changes, unreadable/no
image, equal-size cache invalidation and per-build reproducibility. No additional
plugin Python changes were made during this review.

## Evidence locations and identity

Historical evidence is preserved under
`/Users/thierryc/Dev/github/thierryc/Glyphs-mcp-worktrees/v2/reports/v2-release-readiness/m33-build13-20261005`.
Its archive SHA-256 is
`27b66cb2c3831be1e4c3b508245718feb4fa29d08d02a688bc46ea56c4ef36d7`.
Its payload inventory hash is
`677480df3ab33b887849c2f2055072811b25fe334dadfb527ff77683821a9992`.
These identify the earlier installed candidate, not a subsequent documentation
repackage. The report, handoff, patch, tests and archive were not overwritten.

Fresh review evidence is under
`.build/qualification-build13-20261005` in the prepared worktree, including the
initial diff/test backup, test logs, scaffold receipt, native harness and logs.
Historical review packages are retained as `candidate-a` and `candidate-b`.
After the authorized local commit, `committed-a` and `committed-b` hold the
clean-source candidate. Their manifest/checksums and `committed-handoff.json`
identify its exact revision.
A content-addressed evidence inventory accompanies the handoff.

Host native backend: macOS 26.7.1 (25G309), arm64, Glyphs 4.1.1/build 4108
(app metadata; runtime reports 4.1/4108.0), official Python 3.14.6,
zlib 1.2.12. Detached objects only: no installed plugin/open font used.
Engine: `/Library/Application Support/beztrace/bin/beztrace`, stable 0.1.1,
SHA-256 `3695e8fa41e941a21003052add1b65aea758fb8cd72addfd037288a94265e0cf`.
Stable tag `v0.1.1` still resolves to commit
`9737f21fabfda0dc9e6728bd34df2f83380238e9`.

Visible VM: `Copy of Macos-14`, macOS 14.6.1 arm64, Glyphs 4.1.1/build 4108
trial, official Python 3.14.6. Existing installed candidate only; About displays
0.1.0/build 13, with no manual PythonCache clearing. Disposable font only:
`M33 Build13 Disposable`. No new installation/relaunch occurred. The chosen
engine in the UI was the existing stable 0.1.1 executable under
`/Applications/Glyphs MCP Undo Beta.app/Contents/Resources/Beztrace/beztrace-0.1.1/bin/beztrace`.
The existing installed/loaded receipts apply to the historical payload. This run
visually reconfirmed About identity, but does not establish installation of the
new documentation-containing archive.

## Results and limits

| Check | Result | Evidence / scope |
| --- | --- | --- |
| Companion tests with stable engine corpus | Pass, 113 tests | `tests.log`, 50.880 s |
| Scaffold and product boundaries | Pass | `scaffold.json`; source loader universal/pinned |
| Package/schema/inventory/checksums | Pass for reviewed candidate | See exact-identity handoff; repeat ZIP and inventories checked per revision |
| AppKit controls and live replacement safety | Pass with WindowServer access | `appkit-windowserver.log`; fake host, not installed plugin |
| Sandbox AppKit attempt | Aborted before assertions | `appkit-sandbox.log`; not a pass |
| Real native affine placement | Pass, nine cases | `native-canvas.log`; crop, DPI, EXIF, foreground/background, image/path Undo/Redo, zero-width backend, async fit |
| Real native replacement and exact Undo/Redo | Pass | `native-safety-final.log`; detached zero-width layer |
| External width/crop/transform/alpha/lock edits | Pass, reject without writes | Same log, real native objects |
| Identical image replacement / changed source file | Pass, identity/content rejection | Same log, scratch fixture only |
| Cancellation | Pass native API; live UI pending | Same log; completed plan cancelled before apply. UI attempt finished before cancellation could be observed |
| Invalid options | Pass native API; bounded UI observation | Same log; invalid accuracy rejected before writes. VM invalid text restored prior valid value on focus loss |
| Recovery failures | Pass, injected | Same log; insertion failure restores native state; failed restore raises RecoveryError and closes undo group. Harness restores detached fixture afterward |
| Fresh PNG/JPEG first-click, Done, Undo/Redo | Pass for historical installed payload | Prior report: 17 native assertions across eight states |
| Live preset change Balanced to Sharp | Visually passed for installed payload | VM panel shows Sharp, smoothing 0.7, two traced contours and Done. No fresh exact native readback collected for this change |
| Live target switching and external edits during work | Pending installed UI | Fake-host coverage does not complete this gate |
| Live zero-width panel behavior | Pending | Earlier native component navigation changed B width to 700; backend zero-width pass is insufficient |
| Intel | Explicitly deferred | Universal loader architecture check is not Intel execution |

The initial safety-harness attempts failed due to harness undo grouping and a
harness NameError. Both logs are retained; the corrected harness passed all 12
cases. No product workaround was introduced. A bounded guest collection returned
only historical observer rows, so no new UI readback assertions are claimed.

## Remaining gates and next action

The local commit is authorized. Freeze its clean revision and reproduce the
unsigned package twice. A remote source URL is
pending separate push authorization; the base URL must not represent dirty
build-13 changes. Qualify the exact final bytes and installed/running identity,
complete live cancellation, target-switch/external-edit, recovery-panel and
zero-width cases, and retain Intel as deferred until actual Intel execution.
Fresh-host Python setup, install/update/rollback/removal, accessibility,
independent Developer ID signing, notarization, Gatekeeper acceptance and
publication remain release gates under separate authorization.

No stable-engine, public MCP API or dependency changes were made. No automatic
installation, user-font edits, remote upload, signing or publication occurred.
