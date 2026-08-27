# Milestone 6 viability review

Milestone 6 is a decision checkpoint, not a mechanism for weakening a failed
gate. The review consumes the immutable reference, the complete corpus,
performance and robustness evidence, and the staged standalone artifacts. Its
machine-readable result is generated outside the repository by
`scripts/verify_viability.py`.

## Current decision

**Reject merge and publication until the remaining blocking gate passes.**

The implementation is not eligible to merge into `main` or become a Glyphs
MCP dependency while any required gate is pending, failed, missing, or outside
the authorized boundary. The current checkpoint has one known required
blocker: the universal ZIP and installer are unsigned and unnotarized.
Developer ID use, notarization, and installation have not been separately
authorized.

The project owner completed trace-quality acceptance for all 100 images,
including six accepted-with-optical-notes decisions. All five single-shot
1024×1024 CLI p95 measurements are below one second. The complete optimized
Apple Silicon and x86_64/Rosetta suites pass, and the focused malformed-input
AddressSanitizer test passes with the installed Xcode beta toolchain. The
project owner explicitly approved merge, but that approval does not waive the
signed-artifact requirement. Publication remains a separate authorization
after merge eligibility; Milestone 6 does not grant it.

## Review evidence

The complete-corpus report is generated on the external work volume:

```sh
swift build --configuration release
python3 scripts/trace_corpus_review.py
```

For each of the 100 frozen inputs it performs two JSON, two baked-SVG, and two
preserve-SVG traces. It rejects nondeterministic bytes, source-hash mismatch,
non-finite output, open or empty paths, and declared contour-count mismatch.
Its local HTML page shows the source, both production SVG modes, and a padded,
transform-free node/handle/direction overlay. Review selections persist in
the browser and export as `trace-acceptance.json`, cryptographically bound to
the corpus manifest.

The packaged workflow check extracts the staged ZIP into a temporary directory
and uses only its bundled executable to produce JSON and default baked SVG:

```sh
python3 scripts/verify_packaged_workflow.py
```

The final evaluator reads evidence without changing it:

```sh
python3 scripts/verify_viability.py
```

Use `--require-approve` only when every required gate is expected to pass. It
returns nonzero for a reject decision. Signing, merge approval, and publication
flags may be supplied only after the project owner grants those exact
authorizations.

## Gate interpretation

| Gate | Required outcome | Current checkpoint |
| --- | --- | --- |
| Optimized tests and clean-worktree replay | All pass, no rewrite | Pass: arm64, x86_64/Rosetta, and focused ASan in a detached clean worktree |
| 100-image automatic trace checks | 100/100, twice, deterministic | Pass |
| Human trace acceptance | At least 95/100 | Pass: 100/100 accepted; six carry optical notes |
| Swift/Rust performance | Median and p95 at most 1.5× Rust | Pass in recorded evidence |
| Absolute process time | Every fixture p95 below 1 second | Pass: 5/5; recorded p95 range 280.770–702.895 ms |
| Peak RSS | Every fixture below 256 MiB | Pass in recorded evidence |
| Cross-architecture output | 100/100 byte-identical | Pass in recorded evidence |
| Malformed-input campaign | At least 50,000 safe rejections | Pass in recorded evidence |
| Product and license boundary | Standalone, system-only runtime; SPDX/notices complete | Pass in repository audit |
| Universal distribution | arm64 and x86_64 | Pass for unsigned candidate |
| Signing and notarization | All artifacts verified | Not authorized; not complete |
| Packaged non-Glyphs workflow | JSON and SVG succeed | Pass |
| Merge approval | Explicit project-owner approval | Pass |

The report records evidence status exactly. It does not infer approval from a
successful build, ignore a missing file, convert an unauthorized identity step
to a pass, or treat publication authorization as implicit.

## Remediation order

1. Obtain separate authorization for Developer ID signing, notarization, and
   installation testing, and make valid signing identities available on the
   build host.
2. Build and verify the signed universal ZIP and notarized installer.
3. Re-run all evidence at the final implementation commit and require the
   formal decision to be `approve`.
4. Merge the implementation branch into `main`. Request publication
   authorization separately after merge eligibility.

No Glyphs MCP adapter work begins during this remediation.
