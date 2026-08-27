# Test workflow

## Test-first rule

The reference checkpoint must remain reproducible throughout implementation.
Tests read fixtures but never rewrite them. Fixture generation and oracle
capture are explicit maintenance operations whose diffs require review.

## Fixture corpus

The release-candidate corpus contains 100 reviewed-source 1024x1024 PNG files:
50 deterministic and 50 generated inputs, comprising 64 glyphs and 36 symbols.
The 24-image initial corpus remains part of that set. `Tests/Fixtures/manifest.json`
records source, prompt or accurately labeled prompt summary, license, source
and normalized checksums, selection evidence, topology, and structural
expectations. Source selection and traced-output acceptance are separate
review states.

Regenerate the deterministic half with the bundled Python runtime:

```sh
python3 scripts/generate_deterministic_fixtures.py
python3 scripts/generate_deterministic_fixtures.py --check
python3 scripts/promote_generated_fixtures.py --check
python3 scripts/verify_fixtures.py
python3 scripts/verify_milestone5.py
```

The pinned source files live beside their license texts in
`Tests/Fixtures/sources`. Do not replace them with an unpinned web download.
The 38 added generated concepts were produced as two-candidate pools under
`/Volumes/T9/beztrace/milestone-5`, selected by the project owner, then
normalized through the explicit promotion command. The committed selection
and selected-source manifests pin the candidate number, original SHA-256, and
normalized SHA-256. Candidate pools and trace-review output stay on the
external volume.

Build the read-only traced-output review after an optimized build with:

```sh
python3 scripts/trace_generated_review.py
```

The command traces every newly selected source twice in JSON and SVG, rejects
nondeterministic, non-finite, empty, open, or source-hash-mismatched results,
and writes baked and preserve-mode SVG renders plus review-only padded
node/handle/direction views to the external Milestone 5 report directory. The
report labels each contour's JSON Y-up winding and reflected baked-SVG winding
so direction is not inferred from rendering alone. It never marks a trace
accepted. Test the report generator without tracing fixtures with:

```sh
python3 scripts/trace_generated_review_test.py
```

Milestone 6 expands that review to the frozen 100-image corpus:

```sh
python3 scripts/trace_corpus_review_test.py
python3 scripts/trace_corpus_review.py
```

The generated report stays under `/Volumes/T9/beztrace/milestone-6`. Its four
views compare the raster source, default transform-free SVG, preserve-mode SVG,
and a review-only transform-free node/handle/direction overlay. The overlay
bakes every on-curve, off-curve, control handle, and arrow coordinate and adds
an explicit padded view box; it does not use an SVG transform group. All
contours share one compound filled path so nonzero winding keeps counters open
instead of painting them as separate black shapes. The page
exports a manifest-bound human acceptance document but never edits committed
fixture state.

After building both release architectures, compare the serialized JSON for
the entire corpus with:

```sh
python3 scripts/verify_cross_arch_corpus.py
```

The Milestone 6 checkpoint records byte-identical arm64/x86_64 JSON for all
100 fixtures. The optimized XCTest suite passes 84 tests on both Apple Silicon
and x86_64/Rosetta with zero failures and one explicit maintenance-export skip.

## Rust reference

The only oracle is img2bez commit
`23073ca08ecdac61ad0e838bfae49a590bc2c7cc`. Its archive checksum and gate
parameters are recorded in `Tests/Fixtures/oracle/v1/reference.json`.

```sh
scripts/capture_img2bez_oracle.sh
```

The script selects Rust 1.88 by default and refuses older toolchains. The
pinned OFL source is bundled under `oracle/v1/reference-source`; before any
capture it must pass `scripts/check_reference_ufo.py`, which checks all 62
glyphs and the focused baseline's recorded on-curve counts. An override must
provide its license and provenance explicitly.

The public-history scan originally produced a false negative because it looked
for literal digit characters instead of canonical UFO glyph names (`zero`
through `nine`). After correcting that check, Virtua Grotesk commit
`797c1065abd0c1318217b7c44aff3d61074f7280` matches the complete focused
fingerprint and contains all 62 glyphs. Validate and inventory any candidate
with:

```sh
python3 scripts/intake_reference_ufo.py /absolute/path/to/reference.ufo \
  --license 'reviewed license' --provenance 'upstream delivery/revision' \
  --received YYYY-MM-DD
```

The deterministic observation-only patch is pinned at
`Tests/Fixtures/oracle/v1/reference-patches/0001-stage-capture.patch`. It is
applied only to a temporary checkout, disables parallel capture ordering, and
does not change tracing algorithms or defaults. Stage JSON formats are defined
under `Tests/Fixtures/oracle/v1/schemas`.

The 24-image Rust evidence, benchmark, and complete oracle can be checked
independently without rewriting them:

```sh
python3 scripts/verify_oracle.py
```

`--allow-incomplete` is reserved for developing a future oracle version. CI and
the normal test workflow require the complete hashed v1 manifest.

Capture, for all 62 Basic Latin glyphs, the prepared raster, subpixel contour,
structural plan, fitted outline, refined outline, cleaned outline, final JSON
and SVG, diagnostics, timing, and structural report. Store versioned immutable
results in `Tests/Fixtures/oracle/v1`; use `test-work` for transient overlays
and comparisons.

The beztrace-owned public replacement baseline pins Virtua Grotesk commit
`797c1065abd0c1318217b7c44aff3d61074f7280` under OFL-1.1. It exactly matches
the recorded focused fingerprint and establishes a measured acceptance floor
of 62/62 passing with mean structural score at least 0.961. The upstream 0.964
figure remains historical and unreproduced; it is not a release blocker.
Coordinate deviation may not exceed 0.25 canonical units before
snapping or 1 unit after snapping.

## Swift pipeline

The Swift package covers deterministic geometry, bounded PNG/JPEG preparation,
subpixel contours, structural planning, constrained cubic fitting, raster
refinement, ordered typographic cleanup, and validated internal outlines. It
also covers the neutral public API, explicit placement, deterministic JSON/SVG,
and the standalone command-line adapter. Run the complete optimized XCTest
gate on the current architecture with:

```sh
swift test --configuration release --disable-swift-testing
```

The package uses XCTest only; disabling Swift Testing avoids launching an
empty second runner and is required for the local Rosetta cross-architecture
command:

```sh
arch -x86_64 swift test --disable-swift-testing \
  --configuration release \
  --triple x86_64-apple-macosx13.0 \
  --scratch-path .build/x86_64-target
```

The gate includes exact point comparison for all 62 Basic Latin subpixel
captures; exact split kinds, indices, line sections, topology, and ordering for
all 86 structural plans; and topology-preserving numeric comparisons for the
86 initial and raster-refined fits. All 62 cleaned/validated captures are
checked after scaling and snapping, and all 24 reviewed glyph and symbol images
must trace twice to identical finite, closed, correctly wound internal
outlines. The complete 100-image corpus must trace twice to identical finite,
closed outlines with its declared contour counts. CI runs the optimized suite
on native Apple Silicon and Intel hosts.

The test-only evaluator export is an explicit maintenance operation. It writes
only below the caller-selected external work directory and is skipped by
ordinary tests and CI:

```sh
BEZTRACE_EXTERNAL_WORK=/Volumes/T9/beztrace/milestone-3 \
  swift test --configuration release --disable-swift-testing \
  --filter CleanupValidationTests/testMaintenanceExportWritesBasicLatinEvaluationUFO
```

The Milestone 3 candidate export passes all 62 pinned structural reports with
a mean score of `0.964`; the public replacement acceptance floor remains
`0.961`. Overlays, transient evaluation data, reports, and provisional
benchmarks belong outside the repository and are not CI inputs.

## Standalone interface and CLI

The Milestone 4 suite imports the library without `@testable` and exercises the
stable request/result and placement types across the reviewed corpus. It
requires identical repeated `TraceResult` values and JSON bytes, proves JSON
and SVG serialize the same outline stream, validates schema v1, and covers all
placement modes and malformed or oversized input.

CLI tests exercise both the command adapter and the built release process:
standard input and output, path input, batch ordering and the 64-input bound,
JSON/SVG output, diagnostics, JSON errors, stable exit codes, and cross-process
byte determinism. SVG transform-mode tests prove default and explicit bake
equivalence, exact legacy preserve bytes, transform-free baked output, and the
resolved view-box reflection formula for all line endpoints, curve endpoints,
and cubic controls. A test-only M/L/C/Z canonicalizer applies the preserve
matrix and compares both modes point-for-point; focused counter glyphs are also
rasterized with nonzero fill and must have identical coverage. Both modes run
twice across the corpus, and CLI coverage includes streams, files, batch,
invalid combinations, and real subprocess behavior. Process tests must find
the architecture-specific release executable and fail if it is absent; they
never skip silently.

The complete optimized checkpoint includes one intentional maintenance-export
skip. It runs on Apple Silicon and local x86_64 under Rosetta, while CI repeats
the suite on native Apple Silicon and Intel runners. The exact test count and
result are recorded with each checkpoint rather than treated as an interface
contract.
Generated images remain reviewed acceptance fixtures and are never treated as
exact coordinate oracles.

## Viability evidence

The standalone packaged workflow and formal viability evaluator have isolated
unit tests:

```sh
python3 scripts/verify_packaged_workflow_test.py
python3 scripts/verify_installed_package_test.py
python3 scripts/verify_viability_test.py
```

Exercise the staged ZIP without installing it, then write the formal decision:

```sh
python3 scripts/verify_packaged_workflow.py
python3 scripts/verify_installed_package.py
python3 scripts/verify_viability.py
```

Both evidence files are written below the external Milestone 6 work directory.
Missing, pending, failed, and unauthorized required evidence always produces a
reject decision. `--require-approve` makes that decision fail the command for a
release-gate invocation.

For a final local checkpoint, run the complete command matrix from a detached
clean worktree:

```sh
python3 scripts/run_viability_tests.py
```

The evidence records every command, exit status, duration, bounded output tail,
revision, and clean-worktree state. The normal run includes optimized arm64,
x86_64/Rosetta, and AddressSanitizer tests. If the stable Xcode sanitizer
runtime is rejected by local macOS platform-signature policy, select another
installed Swift toolchain explicitly rather than skipping the gate:

```sh
python3 scripts/run_viability_tests.py \
  --asan-swift /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
```

The final Milestone 6 local evidence uses that Xcode beta toolchain for the
focused malformed-input AddressSanitizer run; every other command uses the
default project toolchain.
