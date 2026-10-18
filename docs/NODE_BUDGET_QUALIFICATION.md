# Point-budget development qualification — 2026-10-09

Owner-authorized `lit/master-matching`; engine/companion `0.2.0-dev.1`.
Implementation, tests and unsigned packaging only. Previous distributions and
development artifacts are preserved. This does not qualify a stable release.

## Implemented behavior

- Zero extra reference on-curves by default. Shared subdivision spends only an
  explicitly selected allowance, across the entire glyph.
- Independent total-node ceiling includes handles and degree elevation. The
  panel starts at 125% of the reference count; standalone default ceilings are
  64 on-curves and 64 total nodes. Both can be explicitly changed.
- Existing reference knots/geometry are retained. Persistent corners and
  paired landmarks are protected. Free target knots/handles are optimized before
  subdivision. Refinement follows fitting error; redundant inserted cuts are
  removed jointly. Smooth-join polishing stays inside the original error limit.
- Fixed-reference structure and fitting accuracy remain hard constraints.
  Exceeding a budget returns a failure, never an oversized successful result.
- CLI capability negotiation, schemas, file exchange, import revalidation and
  final Apply guards include the budget. Matching-only review preserves its
  already-compatible structure without adding points.

## LeftyNote evidence

The original frozen local generated images and original Regular outlines are
reused without modifying the original font. Local artifacts are under
`test-work/leftynote-node-budget-20261009/`, excluded from distribution.

| Glyph | Original nodes | Earlier matching | New matching | Added on-curves | Boundary deviation |
| --- | ---: | ---: | ---: | ---: | ---: |
| a | 44 | 142 | 51 | 1 | 0.855 |
| n | 34 | 128 | 42 | 2 | 0.987 |
| o | 45 | 104 | 51 | 0 | 0.863 |

These results use an explicit two-on-curve allowance and a one-unit fitting
tolerance at 1000 UPM. Extra handles from exact line degree elevation account for
some total-node growth. No fitting tolerance was automatically increased.

Native HOI qualification remains separate: n passes with three ip entries and
less than five units of intermediate movement. The economical a has an
unresolved counter join; o reaches the native preparation timeout. Default
combined Apply remains blocked for those cases. Matching-only copies are
explicit local test artifacts, not claims of repaired interpolation. g retains
the previously recorded unsupported source self-intersection.

## Regression and native diagnostics

Full Swift suite: 118 tests, one intentional maintenance skip, no failures.
Later paired-landmark/smooth-polishing changes additionally pass all 18 focused
matching tests. The 100 immutable tracing fixtures are untouched. The frozen
budget-v1 corpus covers mandatory corners versus redundant target knots; tests
also cover global budgets, invalid values, total-handle growth and failed import
or Apply without mutation.

The existing detached Glyphs 4108 native probe continues to cover two-layer
Apply, exact readback, Undo/Redo, rollback, native ip repair and save/reopen.
Candidate cloning now copies the glyph while retaining the detached full font
context. A 1405-glyph LeftyNote context produces byte-equal samples against whole
font cloning at 101 positions, both before and after an ip correction; the
original detached stage remains unchanged. This is not an Intel native test.

Native trials also exposed a detection/verification limit bug. A preserved
endpoint residual can exceed the detection threshold; a repair cannot reduce
the sampled maximum below an unchanged endpoint. Such repairs are verified
against the endpoint residual plus the documented 0.001 allowance. Existing
endpoint residuals with no intermediate excess produce a no-op. Two regression
tests cover both behaviors. Shape, movement, neighboring-join and 201-position
checks are retained.

## Remaining gates

Complete native HOI qualification of economical a/o, installed panel acceptance,
compiled variable-font export, performance/memory qualification and the full
architecture matrix. The earlier cross-architecture floating-point JSON/hash
difference remains recorded; no byte-equality claim is made for complex raster
matches. No installation, relaunch, signing, notarization, merge or publication
is performed by this development task.
