# 0.1.1 stable release qualification

Stable 0.1.1 is public, signed, Apple-notarized and installed. The owner explicitly authorized Apple uploads on 2026-10-05 and completed the required local Keychain and administrator authentication. No distribution gate was waived.

All 27 clean-source qualification commands pass at `9737f21fabfda0dc9e6728bd34df2f83380238e9`. Both arm64 and x86_64/Rosetta execute 100 optimized Swift tests with one intentional maintenance skip and zero failures. All six native GitHub CI jobs pass. All 100 immutable corpus traces reproduce the accepted paths, bounds, statistics and warnings; the original human acceptance is reused unchanged. JSON is byte-identical across architectures. The 50,000-case AddressSanitizer fuzz evidence is reused with an explicit unchanged core/harness source proof. The 107 companion contracts and isolated fake-host AppKit check pass with the final engine. Relative performance, CLI latency and memory gates pass: process p95 349.070–763.480 ms; maximum RSS 28.422 MiB, with three warmups and 30 measurements per fixture and engine.

The final tag/source is `9737f21fabfda0dc9e6728bd34df2f83380238e9`. It preserves the engine and schemas of historical qualified `7e43a0b48fec0634e9393f9f33d2d5cc260ced39`; subsequent source changes add installer identity and isolate CLI tests from historical development artifacts. PR #9 source merge is `1c89f50538cff2351cdb2e4558d1f1e3e7292ceb`.

The original temporary artifacts were unavailable on fresh inspection. New candidates were built without overwriting historical releases. The first new candidate was installed, then preserved when the owner requested installer branding. The final branded candidate was separately signed, notarized, stapled and installed; its exact executable hash matches the PKG and ZIP.

The public API and release page return HTTP 200. Every release asset downloads without authentication and matches its published checksum. Website/download links changed only after these checks.

See the [complete Glyphs MCP v2 handoff](GLYPHS_MCP_V2_HANDOFF.md) for all URLs, hashes, source reconciliation, notarization IDs, metadata and independently unqualified companion status. The [machine-readable evidence](release-evidence-v0.1.1.json) retains measurements and verification records.
