# Verified hybrid fitting (development matching)

The optional standalone matching engine now tries independently implemented
Levien area/first-moment cubic proposals before its existing refined
least-squares fallback. Both pass the same original-source verifier. No external
runtime dependency, public JSON/schema change, tracing-pipeline replacement or
font editing is involved. Graph selection remains future work. [Joint smoothing](JOINT_SMOOTHING.md) is now an explicit, independently verified postprocessing operation.

## Proposal and acceptance

`LevienCubicFitter` normalizes a source interval to a unit chord, integrates its
signed area and chord-direction first moment, and solves a bounded polynomial
for positive tangent-aligned handle lengths. It also considers stationary
near-misses and the removable area-equation pole. Degenerate moments, unsafe
handles and unverified proposals fall through to `MatchingCubicFitter.fit` with
its existing bounded reparameterized refinement. This is an independent
implementation of the mathematics in [Raph Levien's 2021 article](https://raphlinus.github.io/curves/2021/03/11/bezier-fitting.html);
it incorporates no Kurbo source. Candidate root residuals are never an
acceptance certificate.

`SourceGeometryVerifier` owns immutable evidence from original cubic pieces or
an original planning polyline. Convex-hull subdivision supplies bounded
flattening error on each curve; bidirectional polyline distance sampling uses
the 1-Lipschitz distance function to include the maximum possible error between
samples. Both flattening allowances and a floating-point rounding reserve are
included. Sufficient vertex witnesses reject obviously out-of-budget proposals
without dense sampling; their reported upper bound is deliberately loose.
Accepted candidates always receive the complete dense bound. Existing public
pair deviations use this same measurement implementation.

Acceptance also protects directed endpoint tangents and exact endpoints,
existing handle safety, sampled normalized-arc correspondence, and the number
of analytic curvature-sign changes. Ordered samples are a diagnostic, not a
continuous Fréchet-distance proof. Root isolation, flattening, coordinate,
span-count and sampling limits refuse work rather than accepting an unfinished
estimate. These conservative checks can refuse a geometrically usable fit.

## Integration boundaries

Vector matching supplies exact original cubic pieces across each selected
interval. Raster matching uses the hybrid on finalized non-straight sections;
its cheap correspondence search retains the existing fitter. Endpoint connector
segments participate in moment calculation when knots move, but verification
uses the unmodified planning boundary. Existing bounded free-handle/polishing
recovery remains available after a hybrid refusal. Complete outputs still pass
the existing original-source, topology, nesting, budget and sampled
interpolation checks; a locally accepted cubic alone cannot approve a master.

There is no new simplify command or automatic node deletion. Matching still
obeys the chosen reference structure and explicit node ceilings. The historical
benchmark's graph selector remains maintenance-only Python code. Ordinary
single-image tracing and SVG serialization are unchanged.

## Local evaluation

See [the benchmark protocol](../scripts/curve_benchmark/README.md). The
historical exhaustive-union `hybrid` is distinct from the sequential
`hybrid-swift` production fitter. Compare `hybrid-swift` timings only with
`refined-swift-verified`, which includes the same source preparation and
verification workload. Historical raw Swift/Rust proposal timings exclude
those checks.

The benchmark uses the same 28 cases, protected landmarks, six-segment window,
0.5/1/2-unit tolerances, two warmups and eleven repetitions. Report greedy
selection; graph results remain a research control. Exact-subdivision controls
measure recovery of deliberately inserted redundancy and do not predict the
same savings on already clean artwork. The strong synthetic kink must remain
refused. Successful local checks are not release qualification.


## Evaluation on 2026-10-17

On the unchanged 28-case corpus, greedy selection gives these total node counts
on the 27 accepted cases (the pre-existing strong synthetic kink remains
refused):

| Tolerance at 1000 UPM | Refined least squares | Sequential Swift hybrid |
| --- | ---: | ---: |
| 0.5 units | 1037 | 1016 |
| 1 unit | 1016 | 1007 |
| 2 units | 1001 | 992 |

The sequential fitter matches the historical exhaustive union's node count at
all three tolerances. At 1 unit, the extra nine-node saving comes from exact
subdivision controls. Both methods give 319 nodes on the eight clean glyphs and
325 on the eight raster-refined glyphs. The real lowercase e merge requires
the least-squares fallback. R/Y master structures remain unchanged. Historical
proposal geometry, selected outlines and pass/refusal outcomes are unchanged.

A second native Swift timing run after local checks, on the same 94 multi-span
attempts per tolerance, measured median full fit-and-verification calls of
2.495 ms for refined least squares and 2.391 ms for the hybrid at 1 unit.
Summing per-attempt medians gives 256.968 ms and 256.035 ms respectively;
performance is comparable and no application speedup is established.

Local evidence includes the 172-test native suite before final verifier
hardening, 41 final native matching/verifier tests, six benchmark harness tests,
and 18 final native R/Y CLI scenarios. The broad local matrix passed 25/27
commands, including 173 x86_64 tests under Rosetta (two maintenance exports
skipped); Rosetta is not native Intel evidence. The default native matrix test
hit a dSYM permission error, and the sanitizer helper could not load its runtime
under platform policy. Independent native tests/builds passed using explicit
SwiftPM native build/cache options. The existing dirty worktree also prevents
clean-worktree qualification. No release qualification is claimed.
