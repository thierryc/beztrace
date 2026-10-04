# Stable 0.1.1 qualification

The project owner requested a stable version and GitHub publication on 2026-10-04.
That authorizes release preparation, Developer ID signing, Apple notarization,
standalone package verification, merge and publication of 0.1.1. It does not
authorize another version or Glyphs companion installation or publication.

The candidate uses the reviewed tracing fixes already merged into `main`.
Release preparation changes the engine version and distribution tooling; it
does not change the tracing algorithm or the frozen reference fixtures.

Required checks include the complete optimized arm64 and x86_64 suites, focused
AddressSanitizer tests, immutable reference and source audits, 100-image repeated
JSON/SVG and architecture checks, comparison with previously accepted geometry,
50,000 malformed-input cases, same-machine Rust/Swift timing and peak RSS,
signed universal ZIP and PKG inspection, notarization, installed receipt and
standalone JSON/SVG workflow. Machine-readable evidence remains outside source.

The Glyphs companion remains an unsigned development product. Build 12 changes
only exact engine-version compatibility and package metadata; native UI and
companion release qualification remain separate.
