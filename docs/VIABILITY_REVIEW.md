# Milestone 6 viability review

Milestone 6 is a decision checkpoint, not a mechanism for weakening a failed
gate. The review consumes the immutable reference, the complete corpus,
performance and robustness evidence, and the staged standalone artifacts. Its
machine-readable result is generated outside the repository by
`scripts/verify_viability.py`.

## Current decision

**Approve release. Version `0.1.0` publication is separately authorized.**

The implementation is eligible to merge into `main`: every required gate is
present and passing, and the project owner explicitly authorized the merge.
The universal ZIP and installer are Developer ID signed and Apple-notarized;
the installer ticket, Gatekeeper assessment, package receipt, installed binary
hash and signature, and installed JSON/SVG workflow all verify.

The project owner completed trace-quality acceptance for all 100 images,
including six accepted-with-optical-notes decisions. All five single-shot
1024×1024 CLI p95 measurements are below one second. The complete optimized
Apple Silicon and x86_64/Rosetta suites pass, and the focused malformed-input
AddressSanitizer test passes with the installed Xcode beta toolchain. The
project owner explicitly approved merge after the technical gates passed.
The project owner subsequently granted the separate authorization required to
publish version `0.1.0`. Milestone 6 itself did not infer that authorization.

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

The installed-package check verifies the receipt, symlink, installed-versus-
packaged binary hash, universal architectures, Developer ID signatures,
notarization ticket, Gatekeeper acceptance, and installed JSON/SVG traces:

```sh
python3 scripts/verify_installed_package.py
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
| Universal distribution | arm64 and x86_64 | Pass for signed candidate |
| Signing and notarization | All artifacts verified | Pass: both submissions accepted; installer stapled and Gatekeeper accepted |
| Packaged non-Glyphs workflow | JSON and SVG succeed | Pass |
| Installed package | Receipt, hashes, signatures and workflow succeed | Pass |
| Merge approval | Explicit project-owner approval | Pass |

The report records evidence status exactly. It does not infer approval from a
successful build, ignore a missing file, convert an unauthorized identity step
to a pass, or treat publication authorization as implicit.

## Next boundary

Merge the implementation branch into `main` under the recorded authorization.
Version `0.1.0` may be published under the project owner's subsequent explicit
authorization. A Glyphs MCP adapter still requires its own separately scoped
implementation authorization.
