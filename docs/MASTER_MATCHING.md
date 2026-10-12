# Standalone master matching

Version `0.2.0` adds detached matching for one glyph, two masters and one
axis. The engine runs independently of Glyphs and does not write font files.
Ordinary tracing retains the 0.1.1 contract and accepted corpus geometry.
The development companion and native HOI work are not distributed with the engine.

Provide two images of the same glyph at different weights—or an existing Regular
outline and a Bold image—run matching, and review the outlines and intermediate
weights before importing them into your font editor.

## Recommended entry point

Use [the pair workflow](PAIR_WORKFLOW.md) and its versioned file-based job:

```sh
beztrace match-pair JOB.json --output-directory NEW_DIRECTORY --json-errors
```

It handles two images, an outline plus an image, or two outlines. Direct matching
is the default; smart mode compares authorized routes under the same limits.
Optional target/both retracing measures the result against the original vectors
as well as the rendered boundaries. Both outputs, source provenance, diagnostics,
numbered nodes and five interpolation views are retained for review.

A vector reference stays bit-for-bit fixed by default. Tolerance defaults to one
font unit per 1000 UPM; fixed-reference node ceilings derive from its exact
structure. Shared subdivision requires explicit absolute limits and an additional
on-curve allowance. Exact cubic subdivision adds three total nodes; line
subdivision adds one, and line elevation adds two controls. No route silently
raises tolerance, adds handles beyond a ceiling, or unlocks the reference.

Contour pairing uses nesting and geometry. Cyclic starts and bounded monotone
correspondence preserve shape locations before fitting. Counts alone are not
acceptance: review corners, extrema, terminals and open counters. The engine
rejects topology mismatch, genuine crossings, ambiguity and exhausted budgets.
Names and writing systems do not affect the geometry contract.

## Lower-level neutral contracts

Existing neutral `match` requests retain their separate v1 schemas:

```sh
beztrace capabilities --format json
beztrace match REQUEST.json --output RESULT.json --json-errors
beztrace match-plan RASTER_REQUEST.json --output PLAN.json --json-errors
beztrace match-preflight PREFLIGHT_REQUEST.json --output REPORT.json --json-errors
```

- Vector matching: [match request](../Schemas/match-request-v1.schema.json).
- Image matching: [raster request](../Schemas/raster-match-request-v1.schema.json).
- Matched output: [master set](../Schemas/master-set-v1.schema.json).
- Actionable errors: [diagnostic](../Schemas/match-diagnostic-v1.schema.json).
- Source preflight: [request](../Schemas/match-preflight-request-v1.schema.json)
  and [result](../Schemas/match-preflight-result-v1.schema.json).

`trace-to-reference` uses one reference vector and one image. `trace-both` jointly
plans two images and requires shared subdivision. Placement is supplied once as
[a,b,c,d,tx,ty] from the canonical y-up, 1088-height image frame to font units.
The planning result includes original boundary-node IDs; reduced indices must
not be substituted for explicit source-index correspondence.

`preserveStructure:true` reviews existing vector correspondence. It does not
mean fixed-reference raster fitting; raster and pair jobs explain that field's
inapplicability. Use fixed reference and explicit limits for that task.

`match-preflight` examines the reference without fitting or editing it. Its
successful process exit does not mean eligibility; inspect `eligible` and the
performed checks. Ambiguous contours/starts require explicit overrides.

## Fitting and error accounting

Fixed fitting preserves intentional line/cubic structure and original reference
flags/order. Least squares, endpoint/correspondence refinement and bounded
coupled-handle fitting operate within that structure. A failed optimizer is not
reported as proof of mathematical impossibility. [Fitting notes](FIXED_RASTER_FITTING.md)
describe section diagnostics and original-boundary verification.

The section gate remains 15/16 of the declared tolerance; simplification and
flattening reserves are accounted for, and the final complete-source gate retains
the full declared tolerance. Vector-derived extrema are constrained locally;
there is no inferred cap-height trim or undisclosed placement change.

Matching uses explicitly ordered Double distance arithmetic and IEEE square
root rather than platform-dependent hypot results. Sequential-image seeds use
the same neutral matcher as joint fitting. Output coordinates are not rounded to
conceal architecture differences.

## Qualification and limits

The frozen owned corpora under `Tests/Fixtures/matching` exercise vectors, rasters,
point ceilings and correspondence. The R/Y pair corpus covers all three input
combinations and applicable strategies. Source hashes are checked without fixture
regeneration. Tests include line/cubic fitting, genuine refusals, intersection and
topology errors, options, rendering orientation, placement, smart ranking and
real-process CLI behavior.

Local qualification includes 161 optimized arm64 tests (one maintenance skip),
46 focused x86_64/Rosetta tests, 18 controlled pair jobs and a packaged standalone
workflow. Controlled output files match byte-for-byte across both architectures.
Private artwork regressions remain outside public fixtures and downloads.

Sampling is finite. Smooth-join residuals remain advisory and may need visual or
native repair before font application. Neutral results never claim native HOI,
Undo/Redo, save/reopen or exported-font qualification. Native arm64 and Intel CI passed all 161 tests (two expected skips) and all
18 controlled matching cases with identical output files for the preview source.
Stable distribution is separately qualified. See [release status](RELEASE_0.2.0.md).
