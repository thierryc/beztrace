---
name: beztrace-match-masters
description: Explain or use Beztrace to match font master outlines, trace an image to an existing master, and enforce explicit on-curve and total-node limits for interpolation.
license: Apache-2.0 OR MIT
---

# Beztrace master matching

Use when an existing master must guide a new outline's structure or the user
asks how compatible tracing and point limits work. For independent tracing,
use [beztrace-vectorize-image](../beztrace-vectorize-image/SKILL.md). An
explanation request needs no font edits, app connection or engine execution.

## Explain the method

Beztrace extracts the image boundary, then fits it using the reference outline's
structure. It pairs contours by nesting, winding, position and shape; aligns
cyclic starts and corresponding shape locations; and adjusts target knots and
handles within fitting limits. Equal point counts alone do not establish good
correspondence. Check terminals, counters, corners and curve transitions at
intermediate weights before considering kink repair.

Distinguish **on-curves** (points on the outline) from **off-curves** (cubic
handles). Zero added on-curves does not guarantee zero added handles. Exact
line-to-cubic conversion adds two handles while preserving visible geometry.

## Choose the point policy

Resolve the user's meaning of “no extra points” from their request; if unclear,
present these choices and default to unchanged reference structure:

| Policy | Settings and guarantee |
| --- | --- |
| Strict unchanged structure | **Keep reference fixed**, **Extra on-curves: 0**; set the total-node ceiling to the reference's existing count. Reference nodes/types stay fixed; target fitting must use the corresponding structure. |
| Same on-curve count, handles allowed | **Allow shared subdivision**, **Extra on-curves: 0**, with an explicit total-node ceiling. Degree elevation can add handles within that ceiling. |
| Bounded additional structure | Shared subdivision with a user-selected on-curve allowance and total-node ceiling. Exact splits preserve reference geometry; insertion is limited across the whole glyph. |

Count the reference first. Absolute ceilings must contain its existing
structure; a default ceiling is not permission to remove original points.
Never silently raise fitting tolerance or either point allowance. If matching
cannot fit within the selected limits, report the failing contour or section
and measured error. A refusal is a valid outcome.

## Prepare and review

1. Resolve the reference/target, image placement, UPM, axis locations and point
   policy. Use the intended existing font and layers; preserve unsaved work.
2. Check the actual engine's capabilities and loaded companion's support.
   Matching is optional, not implied by ordinary tracing support. Read
   [workflow and contracts](references/workflow.md) for CLI/file exchange,
   native automation, failures or advanced options.
3. For the standalone preview, prepare a versioned pair job and run
   `beztrace match-pair JOB.json --output-directory NEW_DIRECTORY --json-errors`.
   It accepts two images, an outline plus an image, or two outlines. Use fixed
   reference by default and explicit absolute ceilings for shared planning.
4. Inspect `comparison.json`, the recommended matched-master JSON, paired
   on-curves, first nodes, intermediate shapes and original-source deviations.
   Smart mode compares authorized routes only; it does not judge artistic quality.
5. Native font import/application requires a separately qualified adapter and
   user authorization. The standalone preview does not ship matching UI, native
   HOI, or a font writer. Revalidate source/reference evidence and preserve font
   metadata before an authorized native application.

For initial correspondence testing, explicitly prepare matching-only results.
If native HOI repair is selected, unresolved repairs block combined Apply;
disable repair only as an explicit matching-only choice. Preserve existing HOI:
structural edits that invalidate it must be refused. Neutral engine sampling
does not verify native HOI. Imported settings need receiving-context checks.

Report total nodes and on-curves before/after, reference preservation, measured
error, whether HOI was applied, and what native/exported behavior was verified.
Label interpolation checks as sampled; do not claim a continuous guarantee or
release qualification from a successful local test.
