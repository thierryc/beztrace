# Curve optimization research benchmark

Maintenance-only local experiment, authorized 2026-10-17. Nothing here is a
production engine dependency, replacement tracer, font writer or release gate.
Source fixtures remain unchanged. The historical `hybrid` method is the
exhaustive research union. `hybrid-swift` invokes the new sequential production
fitter; `refined-swift-verified` is its equal-workload Swift baseline.

## External reference audit

The reference driver calls the published **kurbo 0.13.1** API as a separate Rust
process. No kurbo implementation is translated into Swift.

- Upstream: https://github.com/linebender/kurbo
- Packaged revision: `838b69ef35f3381cefc007d86aa8364f5a6dc673`, directory `kurbo`
- crates.io archive SHA-256:
  `4b60dfc32f652b926df6192e55525b16d186c69d47876c3ead4da5cc9f8450e2`
- License: `Apache-2.0 OR MIT`; original license files remain in the local
  registry. The driver links the unmodified library only for this experiment.
- Consulted interfaces: `src/fit.rs` (`fit_to_cubic`) and `src/simplify.rs`
  (`SimplifyBezPath`); consult the pinned packaged files under these terms.
- Algorithm references: Raph Levien, *Fitting cubic Bézier curves* (2021),
  https://raphlinus.github.io/curves/2021/03/11/bezier-fitting.html;
  *Simplifying Bézier paths* (2023),
  https://raphlinus.github.io/curves/2023/04/18/bezpath-simplify.html.
- Graph selection is independently written research code inspired by the
  strategy in Peter Selinger's Potrace paper, section 2.4:
  https://potrace.sourceforge.net/potrace.pdf. It is **not** the Potrace
  implementation or a reproduction of its complete algorithm.
- The least-squares candidate uses Beztrace's existing fitter, not a claim of
  exact reproduction of Schneider's Graphics Gems implementation.

Cargo.lock pins all reference-driver dependencies. The runner records compiler,
machine, source/driver/input hashes, configuration, raw candidates and results.
No external source is incorporated into the distributed Swift product.

## Reproduce locally

Requires existing Swift 6, Rust 1.88, Python 3 and NumPy. Offline Cargo needs the
locked packages in the local cache; this command does not install runtimes.

```sh
cargo +1.88.0 build --offline --locked --release \
  --manifest-path scripts/curve_benchmark/reference/Cargo.toml \
  --target-dir .build/curve-benchmark-reference
mkdir -p .build/curve-benchmark-tools
swiftc -O -parse-as-library \
  -module-cache-path .build/curve-benchmark-tools/module-cache \
  Sources/BezierTraceCore/*.swift scripts/curve_benchmark/driver.swift \
  -o .build/curve-benchmark-tools/driver
python3 -m unittest discover -s scripts/curve_benchmark -p 'test_*.py' -v
python3 scripts/curve_benchmark/run.py \
  --output test-work/curve-benchmark-NEW --repeats 11
```

Outputs must use a new directory. `--reuse` requires byte-equivalent decoded
inputs/configuration and reuses raw fitting/verification results for reporting.
Use a fresh directory after changing the verifier or fitting implementation.

The sample is eight frozen Virtua Grotesk vector glyphs, eight captured
raster-refined (pre-cleanup) glyphs, exact two-way cubic subdivision controls
for the same glyphs, frozen R/Y master pairs, and two
independently generated kink controls. All coordinates are at 1000 UPM. This is
a vector simplification/fitting study, not an end-to-end raster-tracer contest.

Every fitter sees the same source spans and endpoint tangents. Least squares
uses 33 samples per source cubic and the existing 8-iteration or bounded
256-iteration routine. Kurbo integrates the same original cubic geometry through
its own API. Fitting samples/integration are part of the competing algorithms;
acceptance uses the common Swift verifier, not either fitter's objective.

Corners over one degree, on-curve axis extrema and line endpoints are protected
in the union of both masters. A six-source-segment window bounds candidate work.
Graph and longest-span greedy selection receive identical accepted edge sets.
Unmodified one-span fallback edges preserve the input when fitting fails.
Graph optimality is only over this finite graph, before complete validation.

Acceptance includes conservative bidirectional source-distance bounds from
PairGeometry (tolerance/200 flattening, tolerance/20 sample spacing with an
allowance), exact endpoints, tangent alignment and existing handle safety.
Independent NumPy diagnostics additionally reject sampled extra inflections and
sampled normalized-arc-length error above tolerance. These sampled diagnostics
are not a continuous curvature/correspondence proof. Final paths are checked
again for geometry, source error and nesting; paired paths must pass all 201
interpolation samples, including the existing 1u tangency-residual threshold.

Legacy cleanup is measured without pretending its fixed internal 4-unit merge
threshold obeys the requested 0.5/1/2-unit limits. Its smooth flags are preserved.
Identity results distinguish pre-existing master kinks from introduced defects.
Smooth flags on pre-cleanup captured paths, which do not encode them, are derived
from measured endpoint tangency within one degree. Protected landmarks use the
same geometry rule for every fitter. The target-only shared-ratio experiment is separate from simplification: it
keeps all on-curves and the reference exact, adjusts target handles by least
movement along their current directions, and reruns the same acceptance checks.

Microtimings exclude source preparation, process launch, JSON, verification and
selection. They include two warmups and the requested repeated calls per job.
Rust/Swift results compare implementations; they do not predict the speed of a
future Swift port. Raw timing samples and compiler/machine identities remain in
the report. Node totals for pairs are per reference master, consistently across
methods; the output preserves matching node/type streams.

## Scope and fairness

Compare fitters on identical original cubic spans, protected boundaries,
tolerances and endpoint tangents; then compare greedy and graph selection over
the same independently accepted candidate edges. Measure fitter time separately
from verification and serialization. Include refusals and unmodified fallback
edges. Comparison is of these implementations on the declared sample, not a
proof of universal superiority, a minimum-node theorem, native font acceptance
or stable release qualification.


## Sequential implementation comparison

The Swift hybrid independently implements Levien's area/first-moment method,
including bounded quartic root isolation, stationary near-misses and removable
area-equation poles. It tries verified Levien candidates before the existing
refined least-squares fitter. It does not run graph selection in production.

`hybrid-swift` and `refined-swift-verified` both time source preparation,
sampling, fitting and the same `SourceGeometryVerifier` checks. Their timings
can be compared directly. The historical fitter columns time proposals only
and are not comparable to these complete pipeline timings. The verifier's
safe early distance witnesses may reject a candidate with a deliberately loose
upper bound; accepted fits always receive the complete dense bound.

Use the same 28 cases, window 6, tolerances 0.5/1/2, two warmups and eleven
repetitions. Historical input/case equality and unchanged baseline outputs
must be checked separately. Graph results remain a research control only;
report the existing greedy selection for the production comparison.


To compare against an unchanged historical run and repeat only the comparable
Swift multi-span timing workload after other checks have finished:

```sh
python3 scripts/curve_benchmark/compare.py \
  --before PATH_TO_HISTORICAL_REPORT --after PATH_TO_NEW_REPORT \
  --output PATH_TO_NEW_REPORT/comparison.json
python3 scripts/curve_benchmark/retime.py --report PATH_TO_NEW_REPORT
```

The timing repeat checks core/binary hashes and requires identical proposal
geometry and selected fitter choices. It saves the filtered inputs, raw timed
candidates and a separate summary; the original full benchmark remains intact.


## Joint smoothing comparison

`hybrid-swift-smoothed` postprocesses the existing greedy hybrid result using
`JointMasterSmoother`, with the reference fixed and the immutable original target
as `sourceTarget`. Node counts/types, flags and on-curves are asserted unchanged.
Single-master samples are not applicable. A requested smoothing refusal counts
as a refusal for this combined method, even when retaining the input geometry
would remain acceptable for matching alone. Compare node counts only over the
same accepted cases; smoothing itself never removes nodes.

`joint-smoothing-inputs.json` and `joint-smoothing.json` retain actual requests,
results, source bounds, before/after residuals and eleven complete operation
timings after two warmups. These include all smoothing verification. Accepted
proposals receive one full 201-position geometry/nesting sweep, with a lightweight
before-residual diagnostic; refusals may exit earlier. They measure
a different operation from raw fitting. The historical Python ratio trial is a
separate control. Production graph selection remains deferred.
