# Fixed-reference raster fitting investigation

Local development work on `lit/master-matching`, 2026-10-12. Published releases,
tags and distributed bytes are unchanged. Private font outlines and artwork
remain outside committed fixtures.

## Cause and correction

Fixed structure is a fitting constraint, not evidence that a failed numerical
fit is mathematically impossible. The investigation exposed an eight-step cubic
reparameterization limit, line endpoints constrained to the raster boundary,
and smooth line/curve transitions treated as ordinary free fitting knots.
Least-squares fitting also minimizes mean error rather than the maximum error
used for acceptance.

The original path remains first choice. Only a failing fixed-reference request
uses the bounded fallback:

- Certify the existing reference as a target candidate against the original
  placed boundary. A sufficiently close image can already be represented by
  this known structure; an inferior fitted replacement need not be accepted.
- Retain the best safe cubic candidate during up to 256 reparameterization
  steps, with free or measured tangent directions. Stop at the unchanged budget.
- Fit intentional lines with a minimum-width enclosing strip. Its half-width
  supplies a lower bound for that assigned span. Share endpoint changes with
  both neighboring sections and measure their joint errors.
- Refine smooth line/curve transition locations inside the existing 0.025
  feature-anchor neighborhood. Other free knots retain the 1/64 neighborhood;
  locked corners, extrema and explicit cyclic starts remain protected.
- Refine existing handles against maximum deviation. Preserve the placed
  image's vertical extent using minimum bounded control adjustment and refit
  affected curves. Numerical bounds use a 64-ULP rounding allowance scaled by
  height; this is not a font-unit fitting allowance or a cap-height trim.

No nodes, handles or degree elevation are added under fixed reference. Original
reference coordinates, order, winding, types and smooth flags are returned
directly. Raster preparation, thresholding, canonical normalization and the
supplied affine are unchanged.

## Error accounting and diagnostics

The section gate remains `fitTolerance * 15/16` (0.9375u for a 1u request).
Boundary simplification remains bounded by `fitTolerance/16`. The final gate
measures the complete fitted outline against the **original** boundary, uses
flattening at `fitTolerance/32`, adds twice that flattening allowance, and
requires the reported deviation to stay within the full declared tolerance.
Section acceptance alone is not the final error certificate.

Optional diagnostic fields `section`, `measuredDeviation`, `allowedDeviation`,
`cause` and `boundarySpan` supplement original node locations and fitted/source
attribution. Boundary IDs identify raw extracted points, not reduced selector
indices. Failure stdout remains empty; invalid options exit 2 and geometry or
unestablished fitting exits 5. `fit-not-established` deliberately does not claim
an impossible representation from optimizer failure alone.

`options.preserveStructure` is for reviewing existing vector correspondence.
Raster matching rejects it with a field-specific explanation. Select **Trace
image to reference**, **Keep unchanged**, and explicit on-curve/total-node
ceilings for strict compatible tracing. The panel derives the on-curve ceiling
from the actual reference count plus the explicit extra-point allowance,
separately from the total-node ceiling that includes controls. **Review compatible outlines** is a
separate vector operation. Preparation does not apply anything natively.

## Reproduction and review

Public synthetic tests cover cubic convergence, line rotation/centering, a true
line-representation lower bound, structured fixed-fit refusal and option errors.
Existing crossing and topology tests remain required. Private replay additionally
checks exact IEEE-754 reference coordinates, every frozen handoff hash, actual
node/type budgets, affine/source provenance, vertical extent and 201 sampled
interpolation positions. Set explicit local directories to run it:

```sh
BEZTRACE_PRIVATE_HANDOFF=/absolute/private/handoff \
BEZTRACE_FIT_EVIDENCE=/absolute/local/evidence \
  swift test -c release --disable-swift-testing \
  --filter RasterFitInvestigationTests

python3 scripts/qualify_private_raster_fit.py \
  --handoff /absolute/private/handoff \
  --engine /absolute/candidate/beztrace \
  --baseline /absolute/retained/beztrace \
  --output /absolute/new/replay-directory
```

The private replay is explicitly skipped when its two directory variables are
absent; it is not silently counted as executed. The CLI qualifier retains every
stream/exit code and writes actual successful master-set JSON and a build receipt.

The local acceptance record is under ignored `test-work/leftynote-a-20261012`:
root cause, section coordinates/spans, independent bounded measurements,
numbered overlays, 400/500/600/700 proofs, patch and native integration directions.
Neutral sampling is not native HOI, native application, a continuous interpolation
proof, or release qualification. Native writes, Undo/Redo and save/reopen require
separate authorization and verified receipts.
