# Beztrace 0.2.0 standalone release

Published on 2026-10-12 with explicit owner authorization, Developer ID signatures
and Apple notarization. The [public release](https://github.com/thierryc/beztrace/releases/tag/v0.2.0)
is pinned to source `0344b8d6c1935b9de3009cbd46257bfa99060b8a`.
Previous release tags and distributed bytes remain unchanged.

## Distribution checks

- All seven assets download anonymously and exactly match qualified local bytes.
- ZIP SHA-256: `07b00b1cf16c24f4bdcce55f3f0c351a291e24ae1b9d2704c3b705f323d6fff7`.
- Stapled PKG SHA-256: `48a1dbebb4ddb6d05c56fc2a856a0b278db378359859c84ccaf2508fc8618259`.
- Signed universal engine SHA-256: `5aaab7edc331742edc8fc9cb74436975134a0f651a24831c5cf47ae2828cea81`.
- Apple accepts both submissions; binary signatures, package signature,
  stapled ticket and Gatekeeper assessment pass.
- Disposable macOS 14.6.1/build 23G93 arm64 installation verifies the receipt,
  symlink, exact binary hash, JSON/SVG workflow, and byte-identical installed
  R-mixed-direct and Y-images-smart output against packaged examples.
- Anonymous ZIP verification runs all three input combinations and smart mode
  without installation. The owner's host engine and live fonts are unchanged.

## Local evidence and architecture scope

The clean exact source passes 27 source/tooling checks and 161 optimized tests
on each of native arm64 and local x86_64 under Rosetta, with two expected skips
per architecture and no failures. AddressSanitizer malformed-input checks pass
with an explicitly selected local Xcode beta; a retained 50,000-case sanitizer
campaign covers the identical production source.

All 100 frozen traces and all 18 controlled R/Y matching cases produce identical
outputs on the current signed arm64 and Rosetta executions. Native Intel testing
of revision `6f1d2b5648c10f9028f7560542b439369024c872` is retained separately:
161 tests, two expected skips, no failures, and 18 matching cases whose outputs
also match the current signed results. That earlier check predates the owner's
instruction disabling Actions. `Package.swift` and all production Swift sources
are identical across those revisions; current exact-source Intel execution is
Rosetta, not a new native Intel run.

The current signed executable passes the five-fixture performance and memory
limits. CLI process p95 ranges from 270.530 to 795.819 ms, below one second;
Swift median and p95 remain within 1.5 times the pinned Rust baseline and peak
RSS remains below 256 MiB. Prior owner-accepted 100-image geometry remains equal
under the unchanged production source. Frozen fixtures and tolerances are intact.

The downloadable [qualification receipt](https://github.com/thierryc/beztrace/releases/download/v0.2.0/qualification-receipt.json),
manifest, SPDX SBOMs and SHA256SUMS identify these results and distributed bytes.
All new checks run locally; repository workflows are removed and Actions disabled.

## Boundaries

This release adds standalone compatible matching. The reference stays exact by
default; node growth and retracing require explicit configuration. Refusals for
incompatible topology, real crossings, ambiguous correspondence and exhausted
budgets remain. Smart mode ranks fidelity and correspondence rather than judging
artistic quality.

Native font application, HOI, Undo/Redo, save/reopen and Glyphs companion support
have their own qualification. The released companion still needs engine 0.1.1;
run the 0.2.0 ZIP independently to retain that installation. The source matching
PR remains separate from the published tag and this documentation update.
