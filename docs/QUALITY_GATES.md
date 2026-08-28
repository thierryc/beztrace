# Quality and viability gates

The gates below are release blockers. A local executable, visually plausible
SVG, or passing happy-path test is not sufficient.

## Reference and differential gates

- Freeze stage and end-to-end outputs from pinned img2bez commit
  `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`.
- Reproduce the 62 Basic Latin reference fixtures used by the upstream
  structural evaluation.
- Match contour topology, outer/counter direction, start normalization,
  line/curve structure, corner/smooth classification, significant extrema,
  inflections, and H/V tangent intent for every fixture.
- Coordinate deviation from the Rust oracle must remain within 0.25 canonical
  units before snapping and 1 unit after deterministic snapping/rounding.
- Preserve or exceed the replacement baseline's measured `0.961` mean
  structural score, with all 62 fixtures passing the same harness. The
  upstream `0.964` result is retained as historical, unreproduced context.

## Generated-image corpus

- Retain at least 100 reviewed clean input images, evenly divided between
  deterministic vector-backed renders and generated sources, with
  prompts/source provenance and stable fixture hashes.
- Cover uppercase, lowercase, numerals, punctuation, counters, multiple
  contours, bowls, diagonals, joins, terminals, sharp tips, near-flats,
  inflections, and simple symbols.
- Require 100% valid geometry and at least 95% acceptance without topology
  repair under a documented review checklist.
- A failure requiring only optical adjustment may be recorded separately; a
  missing counter, wrong winding, self-intersection, false corner/line,
  excessive point count, or unusable handle structure is a topology/structure
  failure.

## Geometry validity

Every successful result must have:

- Finite coordinates and transforms.
- Closed nondegenerate contours.
- Correct outer/counter winding.
- No unexpected self-intersections or zero-length segments.
- Cubic controls in the required node order.
- No loops or uncontrolled handle reach.
- Meaningful extrema and smooth tangent alignment.
- Deterministic contour/node ordering and serialization.
- Equivalent JSON and SVG geometry.

Invalid geometry must fail closed rather than serialize.

## Performance and resource gates

Record hardware, OS, build mode, toolchain, fixture hash, warm/cold state, and
sample count with every published benchmark.

- On the same machine and fixtures, Swift core median and p95 tracing time must
  be no slower than 1.5 times the pinned Rust core baseline.
- End-to-end single-shot CLI p95 must be below one second for 1024x1024 clean
  generated input on the recorded Apple Silicon benchmark machine.
- Peak resident memory must remain below 256 MB for a single 1024x1024 trace.
- Batch processing must cap concurrency and memory and preserve deterministic
  output order.
- Performance may not be achieved by disabling raster refinement, cleanup,
  validation, or diagnostics required by the schema.

## Test matrix

- Geometry primitive and transform tests.
- Image orientation, alpha, grayscale, threshold, inversion, size and malformed
  decoding tests.
- Marching-squares ambiguity, contour assembly, area, direction and start tests.
- Corner/run/extrema/inflection planning fixtures.
- Cubic fit, subdivision, tangent, refinement, cleanup and rounding fixtures.
- Empty, tiny, noisy, oversized, corrupt and unsuitable image failures.
- Repeated-run, cross-process, batch-order, architecture and locale/timezone
  determinism tests.
- JSON schema, SVG equivalence, standard-stream and exit-code tests.
- Property/fuzz tests for bounds safety and non-finite geometry.
- Native `arm64`, native or CI `x86_64`, and universal artifact inspection.
- Signed ZIP, installer, receipt, Gatekeeper, notarization, checksum, license,
  notice and SBOM verification.

## Standalone viability gate

Integration consumers may be planned only after all of the following are true:

1. JSON schema v1 and the CLI are stable and documented.
2. Every required unit, differential, malformed-input and determinism test
   passes.
3. The 62-glyph reference and 100-image generated corpus gates pass.
4. Performance and resource gates pass on recorded hardware.
5. A universal signed executable and notarized installer pass release checks.
6. Checksums, licenses, provenance and SBOM match the artifacts.
7. At least one non-Glyphs workflow succeeds using only the packaged CLI.
8. The implementation branch is reviewed and approved for merge.
9. A versioned standalone release is separately authorized and published from
   the reviewed source revision.

Until then, beztrace is not a viable dependency and Glyphs MCP integration is
prohibited.
