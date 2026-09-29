# Small closed-contour correction — 0.1.1-dev.1

This is a local development engine, not a published replacement for 0.1.0.
The shared released installation and its signed artifacts remain unchanged.
Glyphs companion **0.1.0 build 6** accepts both exact versions and requires the
JSON result version to match the executable's `--version` response.

## Reproduction and correction

The supplied `linked-in-img-blob.png` is a 1006 × 970 opaque PNG with 144-DPI
metadata. Its SHA-256 is
`bca38f856d435c4e0003bdabaeb2bfe439ec629bc0cf53ff36110a48e1354728`.
It remains a private local acceptance input, outside the committed fixtures.
Released 0.1.0 fails at Auto threshold, Invert off: contour 3 has invalid winding.
An isolated diagnostic showed two overlapping line segments before cleanup.
Changing threshold, accuracy or grid did not provide a working trace in the
recorded trials. Disabling refinement also failed another geometry check.

The correction addresses three problems:

- Adaptive smoothing repeatedly tried to reduce the unavoidable mean turn of a
  small closed loop, shrinking its area. Each smoothing candidate must retain
  its original orientation and at least 80% of the resampled enclosed area.
  A rejected candidate leaves the preceding representation intact.
- Closed sample sequences were sent to an open fitter with coincident endpoints.
  Closed fitting now uses four ordered spans. Initial fitting falls back to this
  cubic fit when line substitutions lose orientation or at least half the area;
  fitting-finish changes are retained only when they pass the same guard.
- Winding used only the endpoint polygon. It now uses Green's theorem with
  exact three-point Gauss integration for cubic segments, retaining valid
  two-cubic loops. Collapsed lines still have zero area and fail validation.

The area filter, full geometry validator, public types, JSON schema v1,
pathDataVersion 2 and coordinate convention are unchanged. No contours are
silently removed to make a trace succeed. Existing valid corpus output is preserved.

## Build and use locally

From the repository root:

```sh
swift test -c release --disable-swift-testing
python3 scripts/build_development_engine.py
BEZTRACE_TEST_ENGINE="$PWD/.build/beztrace-0.1.1-dev.1/bin/beztrace" \
  python3 -m unittest discover -s Companions/Glyphs/tests -v
python3 Companions/Glyphs/scripts/package.py --output .build/glyphs-companion-build6
python3 Companions/Glyphs/scripts/verify_package.py .build/glyphs-companion-build6
```

The engine builder requires a fresh output directory (or `--output <new-path>`).
It compiles arm64 and x86_64 for macOS 13, creates a universal local executable,
and records checksums, source fingerprints, revision/dirty state, toolchain and
licenses. It performs no Developer ID signing, notarization, installation or
publication. Historical release tooling remains pinned to the published 0.1.0
release procedure and must not be used to distribute this development build.

Engine path: `.build/beztrace-0.1.1-dev.1/bin/beztrace`.
When the development companion runs from this source checkout, it automatically
selects that executable if it exists and is executable. A packaged companion
outside the checkout retains the shared release as its default; use
**Path → Beztrace… → ⋯ → Choose Engine…** to select the development engine there.
Keep the image on the canvas and trace with Auto threshold and Invert off.

The existing development symlink points to build 7, with build 5 retained
under `.local-archives/glyphs-companion-dev-build5-before-engine-fix` for rollback.
Restoring that payload also requires a relaunch; no relaunch was performed here.

## Verification

- Full optimized Swift suite: **88 tests, one intentional maintenance-only skip,
  no failures**. This includes pinned subpixel, planning, fitting, refinement and
  cleanup differential checks and the 100-image deterministic corpus.
- The final focused suite has **five passing small-contour tests**, including
  an additional invalid-line check and sampled fitting error ≤0.6 for a requested
  accuracy of 0.5 (0.1 allowed for test sampling). The original four regressions
  fail against the unchanged baseline source in an isolated build.
- All **100 released corpus results have exactly identical path geometry** between
  0.1.0 and this candidate. Reference fixtures were not rewritten.
- **95 companion tests passed**, including both accepted versions and rejection of
  a version probe/JSON mismatch. Packaging checks verify deterministic unsigned
  output, manifest, payload inventory and tamper rejection.
- The supplied image produces **48 contours, 673 nodes** both directly and after
  native image preparation. Repeated results agree. Raster intersection-over-union
  is **0.9540**; all 48 above-area-threshold raster components overlap traced ink.
  Pixel differences are within a three-pixel Chebyshev boundary band. The smallest
  component has about 66% ink overlap, so this is a fitted approximation at the
  default accuracy, not exact pixel reconstruction. Overlay review found no lost
  component or spurious guide-line contour.
- The final universal engine is checksum-verified; the supplied image's JSON is
  byte-identical on arm64 and x86_64/Rosetta. Executable SHA-256:
  `c3c92fee43dd45bd6e3a6450e144e4b9932e8af3b48e14a570b1e5a71d93ff73`.
  The final artifact was also used for the disposable native checks below.
- Isolated AppKit panel checks pass with fake font objects and the actual engine.
- Native Glyphs **4.1 build 4107** CLI checks use detached disposable fonts, with
  user plugins disabled. Passed: DPI, EXIF orientation, crop, nine affine cases,
  foreground/background insertion, coordinate readback, source-image/zero-width
  preservation, placement API and native Undo/Redo. The supplied image additionally
  passes native preparation, affine placement/readback, source preservation and
  Undo/Redo. Glyphs reports its logical size as **503 × 485** points.

Local evidence is under `.build/blob-repro`: Swift and companion logs, native
logs, corpus comparison, source hash, JSON traces and direct/native raster overlays.
Failed preliminary runs (test compilation, area-filter expectation and error-text
assertion) were corrected and rerun; they are not counted as passing evidence.

Full visible installed-plugin interaction, screen alignment at multiple zooms,
and user review remain pending. Backend checks do not qualify the loaded plugin
UI. No user font was changed or saved; no release was signed or published.

## 0.1.1-dev.2 local handle-rounding correction

The subsequent local dev.2 candidate retains the small-contour work above and
adds a final safety gate for integer handle rounding. A rounded candidate is
used only when it satisfies the same reach and tangent-intersection limits as
the geometry validator; otherwise cleanup keeps the already capped handles.
This fixes the private blob image at Accuracy 1–3, Smoothing 0.7 and Grid 1,
and the committed sparkle regression at Accuracy 3/Grid 1. The image remains
private and outside tracked fixtures. Schema v1, pathDataVersion 2 and public
Swift request/result types are unchanged.

Build locally with `scripts/build_development_engine.py`; the fresh output is
`.build/beztrace-0.1.1-dev.2`. This candidate is not a replacement for the
published dev.1 prerelease and is not authorized for publication, signing or
notarization.

## 0.1.1-dev.3 topology-safe Grid correction

The local dev.3 candidate retains both earlier corrections and makes coordinate
Grid cleanup best-effort per contour. It builds a validated no-grid fallback,
then accepts requested Grid candidates in stable contour order only when the
shared final validator accepts the complete outline. Rejected candidates retain
their safe fallback geometry and add a deterministic warning; invalid no-grid
geometry still fails closed.

Committed regressions cover collapsed segments and self-intersections at Grid 8,
including the reported Accuracy 0.5, Smoothing 2.5, Corner 13 and minimum-area
700 profile. Schema v1 and public request/result types remain unchanged. Build
locally to `.build/beztrace-0.1.1-dev.3`; this candidate is not authorized for
publication, signing or notarization.
