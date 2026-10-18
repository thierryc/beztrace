# Standalone pair matching (development)

`beztrace match-pair JOB.json --output-directory NEW_DIRECTORY --json-errors`
prepares two compatible outlines and a local review. No font application occurs.
The output directory must not exist; partial work is staged and renamed only
when complete. A geometric refusal writes its comparison report and source
receipts, but no rejected result paths. Exit 0 means a candidate was accepted,
2 means invalid options, 3 means missing/invalid input files, and 5 means no route passed. Input paths resolve
relative to the job file, independent of the caller's working directory.

## Job and inputs

Use `Schemas/pair-job-v1.schema.json`. Exactly two masters and one axis are
supported. The first input is the reference. An outline file is the neutral
`{"contours": [...]}` shape, with closed paths and typed nodes. Image files
require an explicit six-value affine from the neutral y-up, 1088-height frame
to font coordinates; the existing image and transform are never modified.
Components, hints, font metadata and native HOI are outside this interface.

```json
{
  "schemaVersion": 1,
  "unitsPerEm": 1000,
  "axis": {"tag": "wght", "locations": [400, 700]},
  "inputs": [
    {"id": "regular", "kind": "outline", "path": "regular.outline.json"},
    {"id": "bold", "kind": "image", "path": "bold.png",
     "transform": [0.7, 0, 0, 0.7, 0, 0]}
  ],
  "strategy": "smart"
}
```

The transform above is illustrative, not automatic artwork placement.
Default tolerance is UPM/1000, direct strategy, fixed vector reference, zero
additional on-curves, and the exact reference's on-curve/total-node ceilings.
Two-image input defaults to shared planning because no vector baseline exists.
Two images and any unlocked reference require explicit `maxOnCurveNodes` and
`maxNodes`. `maxAdditionalOnCurveNodes` permits only the stated reference growth.
No failed route gets larger limits automatically.

## Strategies

- `direct`: vector matching, reference-guided image tracing, or joint image tracing.
- `retrace-target`: render the second outline and fit to the first's structure.
  Requires two outlines.
- `retrace-both`: render outline inputs and jointly fit both images. Requires an
  outline reference and explicit `referencePolicy: "shared-subdivision"`.
- `smart`: compare applicable routes under the same limits; preserve refusals.
  Fixed vector references never enter a route that retraces the reference.

Two images compare joint planning with sequential tracing of the first image
followed by fixed-reference fitting of the second. The seed uses the same neutral
matcher on two copies of the first image under identical placement and the same
absolute budgets. This keeps the optional matching route independent of ordinary
trace grid/cleanup math and never applies the affine a second time. The sequential seed must
itself pass source fidelity and absolute budgets. An unlocked mixed pair also
compares reference-guided fitting with joint tracing of the rendered reference.

Rendering uses system CoreGraphics/ImageIO, nonzero fill, 2048px height by default,
16px padding, analytic ink bounds and an explicit inverse placement transform.
`renderHeight` accepts 256...4096; aspect ratios over 4096px width are refused.
Rendered bytes, dimensions, pixel scale, fill rule and transform are retained.
Counters are not reconstructed or unioned to make a request pass.

All final outlines are measured against original vectors or original extracted
coverage, independently of the fitting objective. Convex-hull cubic flattening
has a tolerance/200 allowance per curve; polyline samples are separated by at
most tolerance/20. The bidirectional bound adds half that spacing and both
flattening allowances. Vector rendering and fitting therefore share ONE final
source-shape limit, rather than two separately spendable tolerances. Measurement
resource limits refuse excessive flattening or more than two million samples.
Vector-derived results may not expand beyond their original vertical ink envelope.
A subpixel raster extremum overshoot is corrected locally in affected spans,
with analytic extremum constraints and coupled handle fitting against the original
vector. The report records `method: "local-span-constraint"`; `scaleY=1` and
`translateY=0` mean no whole-glyph affine adjustment. Node types remain unchanged.
Images and placement stay unchanged. Both original-source and rendered-boundary bounds
are measured again after this adjustment; a candidate still exceeding either
limit is refused.

## Recommendation and artifacts

Topology, intersections, type compatibility, node budgets, original-source
bounds and 201 linear interpolation positions must pass before ranking.
Fidelity intervals overlapping the best upper bound are measurement-level ties;
rank these by total nodes, on-curves, then excess smooth-join residual relative
to the source outlines. Intentional corners are not smoothing targets. Stable
route order breaks exact ties. This is a geometry recommendation, not an
artistic quality judgement or continuous/native interpolation certificate.

`comparison.json` follows `pair-comparison-v1.schema.json` and records original
source outlines, byte hashes, routes, refusals, deviation intervals, reference/
target unchanged flags and reasons. Each accepted route has master-set JSON and
an SVG with five intermediate positions and numbered endpoint nodes. The
recommended pair is also emitted as separate `reference.outline.json` and
`target.outline.json` files. Input bytes and any rendered images remain available.

`python3 scripts/qualify_pair_matching.py --engine LOCAL_ENGINE --output NEW_DIR`
replays the immutable R/Y control corpus through every applicable route. This
script is a maintenance/qualification helper; Python is not a product runtime
dependency. Legacy `match`, tracing schemas and public stable bytes are unchanged.

Unsigned local packaging is development delivery only. Cross-architecture
matching uses explicitly ordered Double distance arithmetic and IEEE square root,
without coordinate rounding. Compare the actual candidate bytes on both architectures
with `scripts/compare_pair_architectures.py`; passing unit tests alone does not
establish byte determinism. Installation, native font application, signing,
notarization, merging and publication are separate operations.

## Small, explicit node growth

Source masters can start with different counts. Successful output masters need
one common node/type structure, so corresponding nodes interpolate together.
A new shared knot can be added to one or both input structures as needed.
`maxAdditionalOnCurveNodes` counts reference growth across the entire glyph;
`maxNodes` also counts handles. A cubic split adds one on-curve and two controls
(three total nodes); a line split adds one node. Line elevation adds two controls.
This is an allowance, not a command to insert that many nodes.

For a reference with 23 on-curves and 55 total nodes, permit up to two cubic
splits explicitly:

```json
"options": {
  "referencePolicy": "shared-subdivision",
  "fitTolerance": 1,
  "maxAdditionalOnCurveNodes": 2,
  "maxOnCurveNodes": 25,
  "maxNodes": 61
}
```

Choose one split with allowance 1, ceiling 24 and total ceiling 58. A shared
subdivision retains the reference curve shape using exact splits, but changes
its node stream. Use the default fixed policy when the reference must remain
bit-for-bit unchanged. No fallback silently selects shared subdivision. Fixed
policy plus a positive extra-node allowance is a field-specific option error.

`PairMatchConfiguration.resolved(reference:unitsPerEm:)` supplies these same
defaults to Swift clients and the CLI. Agent callers should read `comparison.json`,
require `recommendedRoute`, and consume `recommended.master-set.json`; successful
process execution is preparation, not permission or evidence of font application.

The matcher does not inspect a glyph name, Unicode value or writing system.
Closed line/cubic contours from any script or symbols use the same geometry
contract. Different counter topology, genuine crossings, ambiguity and exhausted
limits still require a refusal or explicit correspondence/artwork correction.
This scope is not a guarantee that every imaginable silhouette can fit every
reference within a finite budget.

## Explicit joint smoothing of compatible outlines

After correspondence is prepared, the standalone `smooth-masters` command can
repair eligible target smooth joins while keeping the supplied reference and
all node types, ordering, flags and on-curves fixed. This is a separate opt-in
operation, documented in [Joint smoothing](JOINT_SMOOTHING.md). It verifies the
complete target against the original vector source under the same tolerance;
a failed proposal returns the unmodified pair and an explicit refusal.

For a vector-to-vector master set, construct a request using its original source:

```sh
python3 - <<'PY'
import json
m = json.load(open('recommended.master-set.json'))
source = next(s['outline'] for s in m['sourceMasters'] if s['id'] == m['target']['id'])
request = dict(schemaVersion=1, unitsPerEm=m['unitsPerEm'],
               fitTolerance=m['options']['fitTolerance'],
               reference=m['reference']['outline'], target=m['target']['outline'],
               sourceTarget=source)
with open('smoothing-request.json', 'w') as f:
    json.dump(request, f)
PY
beztrace smooth-masters smoothing-request.json --output smoothing-result.json --json-errors
```

Inspect `report.status` as well as the exit code. Preserve the original request.
This command accepts vector source outlines; it does not replace the pair
workflow's verification against original raster coverage. Native HOI metadata
remains outside the neutral geometry contract.
