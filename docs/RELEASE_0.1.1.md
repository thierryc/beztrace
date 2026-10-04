# 0.1.1 source qualification and publication status

The project owner requested stable 0.1.1 and GitHub publication, then explicitly
requested merging PR #9 and updating the website and documentation on 2026-10-04.
That latest request authorizes source merge while binary release checks remain
pending. It does not waive those checks or authorize another version or companion
installation/publication. Automatic approval review requires explicit permission
for uploading the ZIP and PKG to Apple; that permission remains pending.

## Verified engineering checkpoint

The source revision `7e43a0b48fec0634e9393f9f33d2d5cc260ced39` passed:

- All 27 commands in the clean detached quality matrix.
- All 100 optimized Swift tests on arm64 and x86_64/Rosetta, with one intentional
  maintenance-only skip and no failures per architecture.
- All six GitHub jobs, including native Apple Silicon, native Intel and ASan.
- The immutable 62-glyph reference, provenance, license and dependency audits.
- Repeated JSON, baked SVG and preserve SVG traces for all 100 corpus inputs.
- Exact paths, bounds, statistics and warnings matching the previously accepted
  corpus; the original human acceptance document is preserved unchanged.
- Byte-identical JSON on arm64 and x86_64 for all 100 images.
- 50,000/50,000 malformed-input rejections under a verified AddressSanitizer runtime.
- All 107 companion contract tests and a packaged standalone JSON/SVG workflow.
- Developer ID signature verification for the universal engine executable.
- All five relative performance, absolute process-time and memory gates.
  Recorded CLI p95: 262.051–710.416 ms; maximum peak RSS: 27.953 MiB.

Benchmarks use the same machine and fixtures, three warmups and 30 measured runs
per fixture, the checksum-matching pinned Rust reference binary, and release
builds. The machine-readable records contain hardware, OS, toolchains, binary and
source hashes, cold/warm state, samples and timings. Evidence is kept outside Git.

## Remaining distribution gates

Installer signing failed because macOS could not obtain local Keychain
authorization. A retry is awaiting local approval. Apple notarization upload was
rejected by automatic approval review because GitHub authorization did not
explicitly cover sending release binaries to Apple. Installation verification
also requires local administrator authentication. The formal viability evaluator
therefore rejects binary publication until those gates pass.

The website retains working 0.1.0 installer/download links while explaining the
0.1.1 source checkpoint. It must switch to 0.1.1 assets only after publication.

The companion remains separately versioned, unsigned and native-unqualified.
Source build 12 adds exact engine 0.1.1 compatibility and is excluded from the
standalone distribution. No Glyphs installation, relaunch or font edit is part
of this release task.
