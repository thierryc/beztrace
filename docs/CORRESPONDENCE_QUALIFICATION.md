# Shape correspondence before HOI

Owner-authorized LeftyNote S correction, 2026-10-09, `lit/master-matching`.
Development engine `0.2.0-dev.1`; published distributions are unchanged.

## Diagnosis and correction

The S starts already described the right-hand side of the lower bowl. Rotating
the entire contour would not repair the later correspondence. Role-only
landmark alignment paired different locations along the lower bowl/terminal;
fitting then moved unassigned knots farther to minimize endpoint fitting error.
The resulting intermediate step was a correspondence error before HOI repair.

The original Swift geometric sequence alignment compares normalized positions
and tangent directions at 128 arc-length intervals. A deterministic dynamic
program uses strictly increasing steps with local stretch bounded to 1/3…3
and global displacement bounded to one third of the perimeter. Compatible
landmarks snap only when this geometric map agrees within 0.025 perimeter.
Cyclic starts compare the full contour as well as the first point. Free target
knots slide within 1/64 of the mapped fraction; subdivision uses the inverse
map to place the reference knot. Accepted redundant splits are pruned before
another insertion. Error, topology, reference preservation and point budgets
remain independent gates. No HOI mathematics or candidate rules were changed.

`Tests/Fixtures/matching/correspondence-v1` freezes a beztrace-owned analytic
serpentine stroke at two widths, with provenance, checksums and acceptance
criteria. Tests cover shape locations, strict ordering/inversion, a misleading
feature label, cyclic starts/overrides, and identical-shape no-ops. Earlier
fixtures are unchanged; private font geometry and artwork are not committed.

## LeftyNote evidence

Private evidence is under `test-work/leftynote-correspondence-20261009`.
The source bold PNG, affine placement, UPM, 1-unit tolerance and prior explicit
six-extra-on-curve / 60-total-node allowance remain unchanged for S.

- Largest paired S on-curve displacement: **447.0 → 56.6 units**. This measures
  correspondence movement, not fitting error or a continuous interpolation bound.
- Both old and corrected results: **57 total nodes / 19 on-curves per master**;
  five added reference on-curves. Reference visible geometry is preserved by
  exact subdivision; all original reference on-curves survive the source map.
- Measured S raster boundary deviation: **0.991345 units**, below the requested 1.
- Seven of eight expanded inputs pass the same previous per-glyph allowances
  deterministically. A fails its existing three-point allowance in a counter
  section (1.04655-unit section error against a 0.9375-unit fitting budget).
  No automatic budget or error relaxation and no replacement A geometry are
  accepted. This remains a regression to resolve before release.
- Native Glyphs **4.1.1/build 4108**, official Python **3.14.6**: matching-only
  detached preparation, exact Apply readback, Undo/Redo, preserved widths/images/
  guides/anchors, save/reopen, and **201 sampled native geometry checks** pass.
  Five ordinary `GSInstance.interpolatedFont` outputs agree with native sampling
  to **0.0000201 units**, with export rounding disabled in the comparison copy.
  Font storage drift is **0.00049784 units**. This is not binary export qualification.
- **No HOI is added to S.** The existing three n settings remain in the copied
  font. The previous HOI audit's n corrections were saved in its separate
  `LeftyNote-HOI-Verified.glyphs`; S's unresolved repair never applied settings.
  The corrected test font is `LeftyNote-S-Correspondence.glyphs`. Original and
  earlier experimental files remain unchanged.

Universal development executable SHA-256:
`6652a9eb6e659eddc9a5e1d11abb70b53ba9de6c0ae274ba6e9c90e1e6e5eb91`.
Source hashes and both architecture slices are recorded in
`.build/beztrace-0.2.0-dev.1-correspondence/development-engine.json`.

The full optimized Swift snapshot passes **122 tests, one maintenance skip**.
The final refinement additionally passes **22 focused matching regressions**.
All **136 companion tests** pass with the new engine; the updated checkout
engine preference additionally passes **16 process/selection checks**.
Both universal slices reproduce the seven successful glyphs with equal node
budgets and at most **2.51e-12 units** of geometry drift. A fails on both.
Matching JSON is not byte-identical across architectures, including source
hash/report differences; the previously recorded determinism blocker remains.
Installed UI, compiled variable-font interpolation, performance qualification,
the A regression and earlier release blockers remain pending. No installation,
relaunch, signing, notarization, merge or publication is included.
