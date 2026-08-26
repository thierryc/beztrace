# Milestone 6 viability review

Milestone 6 is a decision checkpoint, not a mechanism for weakening a failed
gate. The review consumes the immutable reference, the complete corpus,
performance and robustness evidence, and the staged standalone artifacts. Its
machine-readable result is generated outside the repository by
`scripts/verify_viability.py`.

## Current decision

**Reject merge and publication until the blocking gates pass.**

The implementation is not eligible to merge into `main` or become a Glyphs
MCP dependency while any required gate is pending, failed, missing, or outside
the authorized boundary. The current checkpoint has three known blockers:

1. The project owner has not completed trace-quality acceptance for the
   100-image corpus. At least 95 traces must be accepted without topology
   repair.
2. The current single-shot 1024×1024 CLI p95 is below one second for only two
   of five benchmark fixtures. Relative Swift/Rust timing and memory pass, but
   they do not supersede the absolute limit.
3. The universal ZIP and installer are unsigned and unnotarized. Developer ID
   use, notarization, installation, and publication have not been authorized.

Explicit project-owner merge approval is also required after the technical
gates pass. Publication remains a separate authorization after merge
eligibility; Milestone 6 does not grant it.

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
| Optimized tests and clean-worktree replay | All pass, no rewrite | Revalidation in progress |
| 100-image automatic trace checks | 100/100, twice, deterministic | Revalidation in progress |
| Human trace acceptance | At least 95/100 | Pending project-owner review |
| Swift/Rust performance | Median and p95 at most 1.5× Rust | Pass in recorded evidence |
| Absolute process time | Every fixture p95 below 1 second | Fail: 2/5 passes |
| Peak RSS | Every fixture below 256 MiB | Pass in recorded evidence |
| Cross-architecture output | 100/100 byte-identical | Pass in recorded evidence |
| Malformed-input campaign | At least 50,000 safe rejections | Pass in recorded evidence |
| Product and license boundary | Standalone, system-only runtime; SPDX/notices complete | Pass in repository audit |
| Universal distribution | arm64 and x86_64 | Pass for unsigned candidate |
| Signing and notarization | All artifacts verified | Not authorized; not complete |
| Packaged non-Glyphs workflow | JSON and SVG succeed | Revalidation in progress |
| Merge approval | Explicit project-owner approval | Pending |

The report records evidence status exactly. It does not infer approval from a
successful build, ignore a missing file, convert an unauthorized identity step
to a pass, or treat publication authorization as implicit.

## Remediation order

1. Complete the 100-image review and export the acceptance JSON.
2. Fix or explicitly revise the absolute performance requirement through a
   reviewed requirements change; do not waive it inside the evaluator.
3. Re-run all evidence at the final implementation commit.
4. Obtain separate authorization for Developer ID signing, notarization, and
   installation testing, then verify those artifacts.
5. Request explicit merge approval. Request publication authorization only
   after the standalone viability decision is `approve`.

No Glyphs MCP adapter work begins during this remediation.
