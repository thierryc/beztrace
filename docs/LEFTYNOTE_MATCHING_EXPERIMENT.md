# LeftyNote bold-image experiment — 2026-10-09

The owner authorized a disposable copy of LeftyNote and generated bold glyph
images. This experiment exercises actual artwork, not only synthetic fixtures.
The original saved source remains unchanged. Local font and image artifacts
live in `test-work/leftynote-bold-20261009/` and are excluded from source control
and distribution. No license for distributing LeftyNote is inferred.

## Inputs and placement

The actual Regular outlines of `a`, `n`, `o`, and `g` were rendered as a reference
sheet. The built-in image generator produced four bold silhouette drawings.
Individual quadrant crops retain the generated pixels. A recorded uniform
affine places each drawing around its Regular center, extending its visible top
and bottom by ten font units. Generated page layout is not treated as font
placement evidence. PNGs, transforms, input hashes, standalone requests, result
files and native reports remain with the experiment.

## Observed results

At 1000 UPM and a one-unit maximum fitting deviation:

| Glyph | Original nodes | Matched nodes per master | Bold boundary deviation |
| --- | ---: | ---: | ---: |
| a | 44 | 142 | 0.751 |
| n | 34 | 128 | 0.837 |
| o | 45 | 104 | 0.786 |

Shared subdivision preserves the reference's visible geometry and permits
matching these drawings. Fixed-reference fitting rejects these cases rather
than exceeding its structure or geometry constraints. `g` is rejected for a
self-intersection in the original reference; the raster pair also differs in
topology at the original bowl-to-stem join. The generated bold `g` remains an
input for a future explicitly prepared reference. The matcher does not repair
that source topology automatically.

The disposable font has Regular at 400 and Bold Experiment at 700. Only `a`,
`n`, and `o` receive generated Bold outlines; all other Bold layers are copies
of Regular. Path-dependent hints on `n` and `o` were removed from both layers
in the disposable copy, with counts recorded. Product matching still rejects
hinted destinations. The original file and hints are preserved.

Native preparation, committed verification and Undo/Redo pass for all three
letters on Glyphs 4.1.1 build 4108. Native sampling covers 201 positions and
the supported smooth joins. No `ip` correction was needed for these pairs;
this is a useful no-op test, not a new successful repair fixture. The source
font is an incomplete experiment, not a distributable variable font.

## Improvements exposed by the experiment

- Raster tangent estimates now use a physical neighbourhood instead of a single
  marching-squares edge. At identical placement, `n` drops from 353 to 128 nodes
  and `o` from 224 to 104, without increasing the one-unit acceptance tolerance.
- Fixed-reference errors distinguish fit budget, missing corners, handle
  safety and sampled interpolation failures.
- Storage rounding exposed a tangent-triangle fitting heuristic that rejected
  regular short cubics. Matching validation now additionally accepts cubics
  whose derivative control vectors all project forward on the chord and whose
  handle reach obeys the existing bound. Bernstein convexity certifies that
  these curves cannot fold. The published tracing heuristic is unchanged.
- Arc-length inversion snaps exact source knots before inverting cubics with
  vanishing endpoint derivatives. Shared cuts prioritize mandatory reference
  knots over nearby raster landmarks and retain distinct close source knots.

The matching tests include storage-rounding, folded-handle rejection, exact
zero-derivative subdivision, close mandatory knots and a frozen high-resolution
analytical ellipse. Existing frozen fixtures are unchanged.

After these fixes, all three reopened glyphs pass independent core review and
201-position native verification. Captured native image transforms reproduce
the standalone placement, and repeating reference-guided preparation from the
actual Bold canvas succeeds for all three glyphs. The copy is opened in Glyphs.
The full Swift suite passes 113 tests with one intentional skip; the final
matching suite additionally passes 14 tests, including the close-knot change.
The full companion suite passes 132 tests.

The newer universal engine was also tested on these complex requests. Both
slices produce the same structure, but JSON differs by floating-point amounts
up to 4.45e-11 font units, affecting hashes of generated outlines. Byte equality
therefore remains a qualification failure for these cases. Canonical rounding
and source-hash policy need a dedicated correction before release; numerical
closeness is not reported as byte equality.

## Work needed before acceptance

Joint tracing of these complex drawings still produces roughly 676–931 nodes
per master. Improve shared segmentation and point economy before claiming it
is suitable for normal font production. Reference-guided results also merit
designer review of point counts and correspondence. Complete installed panel
acceptance, cancellation/stale-source testing, compiled variable-font export,
and performance qualification. This experiment does not waive release gates.

Build-16 companion archives precede these Swift improvements. Development
engine receipts identify the newer source and unsigned universal executable;
existing candidate and published assets are preserved.
