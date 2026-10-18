# Matching workflow and contracts

## Availability

Discover an existing executable from the configured companion, installation or
authorized workspace. Run `beztrace --version`, then
`beztrace capabilities --format json` on that same executable. An unsupported
capabilities command means matching support is not established; ordinary tracing
may still work. Do not install, build, replace or relaunch software just to explain.

The current extension advertises `matchSchemaVersion=1`,
`rasterMatchSchemaVersion=1`, `nodeBudgetVersion=1`, `maxMasters=2`, `maxAxes=1`,
and `matchModes` containing `outlines`, `review`, `trace-to-reference` and
`trace-both`. Require the requested mode and budget enforcement. Check exact
companion/engine compatibility. Installed, loaded, source and tested versions
are different evidence. Development availability is not publication.

## Standalone pair preview

The 0.2.0-dev.1 engine advertises `pairJobVersion=1`, `pairComparisonVersion=1`
and `pairStrategies`. Use its bundled examples and pair-job schema:

```sh
beztrace match-pair JOB.json --output-directory NEW_DIRECTORY --json-errors
```

The first outline is fixed by default. Two images/shared rebuilding require
explicit absolute node ceilings. Inputs resolve relative to the job; images need
an explicit affine. Direct, target retrace, both retrace and smart are separate
strategies. Require a recommended route and review matched-master JSON and SVG
proofs before import. This preview includes no matching Glyphs UI or native HOI.

## Lower-level standalone use

Use the selected engine's `match-request-v1.schema.json` for vectors and
`raster-match-request-v1.schema.json` for image modes. These are neutral contracts.

```sh
beztrace capabilities --format json
beztrace match request.json --output reviewed-master-set.json --json-errors
```

Input `-` accepts request JSON on stdin; omitting `--output` writes JSON on stdout.
Keep errors separate. A result is a review artifact until an authorized consumer
applies it. Preserve existing output files instead of overwriting them implicitly.

Relevant strict-structure options are:

```json
{
  "referencePolicy": "fixed",
  "maxAdditionalOnCurveNodes": 0,
  "maxOnCurveNodes": 64,
  "maxNodes": 64,
  "fitTolerance": 1
}
```

This is an options fragment, not a complete request. Replace absolute ceilings
with the actual reference counts; 64 is illustrative. For no total-node growth,
`maxNodes` equals the original total; `maxOnCurveNodes` must contain its on-curves.
CLI fitting tolerance is in font units: one unit per 1000 UPM scales with UPM.
The companion's matching tolerance setting uses units per 1000 UPM and scales
the request. Ordinary trace `accuracy` uses canonical units, not this tolerance.

`trace-to-reference` sends one reference outline and one encoded PNG/JPEG.
Placement is a six-value affine map from neutral Y-up, 1088-height coordinates
to the font canvas. Preserve crop, padding and transform; apply placement once.
Ambiguities need explicit contour-pair/start-node overrides based on extracted
paths. `match-plan`, when `rasterPlanningVersion` is advertised, supplies those
paths without fitting.

`trace-both` plans two raster masters together and requires shared subdivision.
It has no existing vector baseline: use absolute budgets, not a promise of zero
extra reference points.

## Native routes

The matching panel prepares detached copies, previews, then applies. It differs
from the ordinary trace panel, which writes on **Trace**.

Only when an independently qualified, compatible matching companion is already
loaded and the user authorizes native automation:

```python
from beztrace_companion.matching import prepare_match, apply_match, export_match

job = prepare_match(
    font, glyph_name, reference_master_id,
    source_mode=1,
    settings={
        "referencePolicy": "fixed",
        "maxAdditionalOnCurveNodes": 0,
        "maxOnCurveNodes": reference_on_curve_count,
        "maxNodes": reference_total_node_count,
        "fitTolerance": 1.0,
        "repairHOI": False,
    },
    engine=engine_path,
)
```

Resolve variables and intended native targets first. `source_mode` is 0 for
outlines, 1 for tracing to reference, 2 for tracing both images, 3 for preserving
compatible structure. Call preparation and `job.advance()` in cancellable
main-thread chunks; do not busy-wait. After `job.done`, inspect `job.error` and
`job.plan`. Apply the reviewed plan once on the main thread; `export_match(plan)`
returns master-set bytes. Never import private test hosts or dynamically load
workspace modules into Glyphs. Use an advertised, documented host edit/script
route; otherwise provide the menu or standalone-file workflow. There is no
implied Beztrace MCP endpoint.

**Import…** maps masters, requires matching UPM and explicit axis mapping,
checks receiving budgets and recomputes native verification. Stored success
claims are not trusted. **Export…** includes reviewed endpoints, correspondence,
source evidence and optional namespaced native HOI. It does not create/save a font.

## Failures and invariants

Keep shared ordering through serialization and application. Independently
normalizing starts afterward can invalidate correspondence.

Topology changes, intersections, open/degenerate contours, unsupported nodes,
components, path-dependent hints, locked targets and intermediate/alternate
interpolation layers are outside current support. Ordinary backups stay intact.
Do not silently decompose, remove overlap, delete hints or close user contours
to make a rejected request pass. Such preparation is a separately scoped design
change with before/after review.

Inspect intermediate outlines for drifting correspondence, folded spans,
collapsed counters and unexpected terminals. Fix correspondence before HOI.
HOI cannot establish node correspondence; only a qualified native evaluator can
verify its correction data. Existing HOI is preserved, not overwritten.

Apply preserves widths, anchors, images, guides, unrelated layers and metadata,
and verifies readback. Stale inputs need fresh preparation. Application failures
need verified two-layer recovery; recovery failure stops further matching writes
for that session. Undo/Redo, save/reopen and binary export are separate checks.
