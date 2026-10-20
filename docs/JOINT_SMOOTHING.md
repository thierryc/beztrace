# Reference-locked joint smoothing

Engine **0.2.2** and companion **0.2.1/build 26** are released as signed,
Apple-notarized universal distributions. All 12 repeated smoothing jobs retain
accepted geometry, reports, original-source bounds and refusals; signed native
UI Apply/Undo/Redo preserves the reference and compatible node structure.
See the [release qualification](RELEASE_0.2.2.md) for exact coverage and the
explicit native Intel waiver. Earlier evaluation checkpoints below are historical.

`JointMasterSmoother.smooth` and the standalone `smooth-masters` command smooth
two already-compatible outlines. The reference is returned bit-for-bit intact.
Only target off-curve coordinates may change. Contour/node order, node counts,
node types, smooth flags, all on-curves and intentional corner handles remain
fixed. No correspondence search, graph selection, node insertion or font editing
is performed. Existing matching commands retain their behavior.

The matching API now also accepts `options.smoothJoins:true` on
`match` (vector, review or raster) and `match-pair`. Omission preserves the
existing behavior and wire output. Check `matchSmoothingVersion:1` and
`hybridFittingVersion:1` before using this option; engine version alone is
insufficient. Successful master sets include `jointSmoothing` and the completed
201-position interpolation report. A refusal returns the normal blocking
`joint-smoothing-refused` diagnostic, without a master set to apply.

Smoothing runs once after fitting and final envelope constraints. Vector jobs
use the original target outline. Raster jobs use the unsimplified, placed image
boundary retained by extraction; the fitted `sourceMasters` snapshot cannot reset
the budget. Pair routes also retain their original vector/raster and envelope
gates. Accepted geometry reuses the smoother's final interpolation sweep. No
second smoothing pass or graph search is added. Companion 0.2.0/build 25 exposes this
as **Smooth compatible joins**; optional native HOI sits in the Interpolation group.

## Use

Use engine **0.2.1** advertising `jointSmoothingVersion: 1` in
`capabilities --format json`. The independently versioned companion integrates
this capability as **Smooth compatible joins**.

```sh
beztrace smooth-masters request.json --output result.json --json-errors
```

The request follows [joint-smoothing-request-v1](../Schemas/joint-smoothing-request-v1.schema.json):

```json
{
  "schemaVersion": 1,
  "unitsPerEm": 1000,
  "fitTolerance": 1,
  "reference": {"contours": []},
  "target": {"contours": []},
  "sourceTarget": {"contours": []}
}
```

Replace the empty illustrative contours with real neutral closed line/cubic
outlines. Supply already-corresponding reference and target node streams.
`sourceTarget` is required: supply the immutable original target artwork,
including when `target` was previously fitted or simplified. For untouched
compatible masters, supply the same outline as target and sourceTarget.
Tolerance defaults to UPM/1000. The command also reads JSON from `-` and writes
JSON to stdout when `--output` is absent.

The [result schema](../Schemas/joint-smoothing-result-v1.schema.json) returns
both outlines, an original-source hash and a report. Status is `smoothed`,
`unchanged`, or `refused`. Successful processing exits 0; a smoothing refusal
exits 5 and returns the original target and reference with its report. Invalid
requests use the normal CLI error stream. Refused proposals are not returned as
editable output geometry. `proposalDeviation` measures the proposed repair,
including on refusal; it must not be mistaken for the returned original target's
error. Retain the original request with the result.

This is an explicit postprocessing operation. Review intermediate shapes before
applying returned paths through a separately authorized font editor workflow.
It does not inspect or preserve native HOI metadata and never claims native HOI.

## Constraint and projection

At a join marked smooth in both masters, let reference incoming/outgoing handle
lengths be I and O. Set alpha=I/(I+O), beta=O/(I+O). The target tangent vectors must
be alpha*W and beta*W for a common vector W. Both masters then share the same
positive handle proportion. Linear interpolation retains collinear tangents
throughout the axis, provided their common vector does not vanish.

For two cubic handles, the target-control least-movement projection is

```
W = (alpha*incomingTarget + beta*outgoingTarget) / (alpha^2 + beta^2)
```

The construction is independently derived from this quadratic objective; no
FontTools or other dependency implementation is translated. Every target cubic
handle belongs to one join, so these projections minimize the sum of squared
control displacement for the fixed reference ratios. This objective does not
minimize maximum outline error.

At line/curve joins, the line's on-curves fix W and only the cubic handle moves.
A two-line join that needs protected on-curve movement is refused. A corner in
either master is preserved. A non-collinear or degenerate reference smooth join
cannot be repaired while keeping the reference fixed and is refused.

The minimum length of the interpolated common vector is checked analytically
on the whole [0,1] interval, with numerical reserve. Endpoint-only or 201-position
sampling alone would miss collapse between sample factors.

## Independent acceptance and atomicity

All join projections are assembled before source measurement. The existing
independent verifier measures the complete proposed target against the original
`sourceTarget` under one tolerance. Original-source distance cannot be spent once
per join or recycled from an intermediate fit. Changed cubic spans additionally
pass local ordered-correspondence and analytic inflection-count checks.
Geometry, handle safety, nesting and all 201 interpolation positions must pass;
smooth residuals must be within numerical precision. On any refusal, all target
edits are discarded. Reapplying an accepted result is idempotent within numerical
precision and still checks the same original source.

The projection is a single closed-form pass over the joins. Only the complete
proposal receives the expensive 201-position geometry/nesting sweep; the
before-residual diagnostic uses point arithmetic alone. Unchanged proposals
still require the complete acceptance sweep and original-source verification.
Input masters are validated individually before projection. Intermediate defects
in the input pair do not trigger a separate pre-repair sweep; the returned pair
must pass all final checks. There is no iterative smoothing search or graph
selection. `sampleCount` describes the interpolation grid; only accepted statuses
establish completion of all acceptance checks.

The handle-ratio relation controls G1 tangency; it does not enforce G2 curvature
or native editor node classes. Topology and nesting checks across the axis are
sampled, not continuous proofs. A failed projection/verification is not proof
that every possible target-only repair would fail.

## Evaluation

Use the unchanged [curve benchmark corpus and protocol](../scripts/curve_benchmark/README.md).
The `hybrid-swift-smoothed` result applies this operation after existing greedy
hybrid fitting, supplies each immutable original target, and retains the full
smoothing report. Single-master cases are explicitly not applicable. A requested
smoothing refusal is counted as refusal, even if keeping the original geometry
would still be valid for matching. The historical Python shared-ratio trial
remains a separate research control. Production graph selection remains deferred.


## Sample results (2026-10-17)

The unchanged 28-case benchmark retains every historical fitting proposal,
selected outline and pass/refusal outcome. Smoothing preserves all node counts;
G1 repair is a separate operation from node reduction.

At 1 unit, the mild synthetic pair's maximum residual over 201 positions falls
from 0.221117 units to about 6.25e-14, with a 0.790079-unit original-source upper
bound and two changed target handles. R/Y are bit-for-bit unchanged. The strong
proposal has an 18.351417-unit upper bound and is refused with both input outlines
intact. At 0.5 units the mild proposal is also refused (0.772579-unit bound),
while at 2 units it passes (0.828051-unit bound). The strong proposal is refused
at all three tested tolerances. These outcomes do not prove every possible
repair would fail.

The combined hybrid-plus-smoothing route accepts 26/28 cases at 0.5 units and
27/28 at 1 and 2 units. A requested smoothing refusal counts as a refusal for
this route, even when retaining original geometry would remain acceptable for
matching. At 1 unit the accepted cases still contain 1007 benchmark nodes.
Single-master samples are not applicable to smoothing. The small paired sample
contains two real R/Y controls and two synthetic kink controls; it does not
establish broad production-font coverage or native font qualification.

Local validation: both the native and x86_64/Rosetta full suites passed 186 tests
(two maintenance skips each). Fourteen final native smoothing library/CLI tests
pass, including adjacent joins that individually fit but jointly exceed one
source budget. All 12 paired sample CLI requests pass schema checks and produce
byte-identical arm64/Rosetta JSON; 18 existing pair-CLI scenarios also pass.
The frozen pre-smoothing verifier accepts all eight successful sample smoothing
outputs. A complete-operation timing repeat after local checks preserves every
result and report exactly (mild 1-unit case median 62.3 ms locally, including
verification). These timings do not establish an application speedup.

The local source matrix passed 26/27 commands. The sanitizer helper's runtime
was blocked by macOS platform policy, and the existing dirty worktree prevents
clean qualification. Rosetta is not native Intel evidence. No release or native
font/HOI qualification is claimed.

An efficiency follow-up replaces the duplicate pre-repair geometry sweep with
the lightweight diagnostic above. The same 28-case benchmark and all 12 smoothing
results/reports remain identical. Two timing rounds in reversed old/new order,
each with two warmups and eleven measurements, reduce the 1-unit mild repair
from 60.34 to 44.86 ms (25.7% less time), R from 21.02 to 10.66 ms (49.3%) and Y
from 0.95 to 0.51 ms (46.1%). These include verification, exclude CLI launch/JSON,
and describe this sample rather than end-to-end application latency. Both full
native and Rosetta suites now pass 188 tests with two skips each, including a
no-change pair whose collapsing midpoint must still be refused. The local
source matrix remains 26/27 with the same sanitizer runtime restriction.
