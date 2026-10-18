---
name: beztrace-vectorize-image
description: Explain or use Beztrace to vectorize clean glyph or symbol PNG/JPEG images into economical editable Bézier outlines, preserving intended scale and placement.
license: Apache-2.0 OR MIT
---

# Beztrace image vectorization

Use for ordinary image-to-outline tracing and explanations of the tracing
workflow. If the new outline must interpolate with an existing master, use
[beztrace-match-masters](../beztrace-match-masters/SKILL.md) before tracing
independently; economical standalone output does not guarantee compatible nodes.

## Choose the route and input

For an explanation, describe the method without modifying files or fonts.
For tracing, resolve the local PNG/JPEG, output (neutral JSON, SVG or native
paths), and intended placement. Beztrace targets clean glyph and symbol
silhouettes with meaningful contrast or alpha. Photo restoration, multicolor
segmentation and noisy-scan cleanup are separate tasks. Preserve original artwork.

Use an existing compatible engine; check its version and supported contract.
Glyphs is optional. Read [workflow and contracts](references/workflow.md) for
CLI flags, quality controls, native automation or coordinate placement.

## Explain and perform tracing

The engine decodes coverage, extracts subpixel contours, identifies structural
features, fits lines and cubic Béziers, refines against the raster, removes
redundant fitting joints and validates the result. It aims for editable
type-design geometry, rather than representing every pixel edge as a point.
Its independent trace may add fitting joints when accuracy requires them; it
does not expose the master matcher's zero-growth guarantee.

- Start with Auto Threshold and the normal quality preset. Use Invert for
  opaque light-on-dark artwork when needed. Meaningful alpha is coverage;
  inspect the resolved source/mask report.
- Keep corners, terminals, counters and small intentional marks visible.
  Increase minimum contour area only for actual specks; punctuation, dots and
  small counters can otherwise disappear.
- Review silhouette, topology, on-curve/handle counts, smooth joins, extrema
  and placement. Adjust accuracy, smoothing or corner sensitivity based on
  observed defects. Preserve the user's choices; do not reduce point counts
  by erasing intentional features or hiding invalid geometry.

In Glyphs, place the image normally on the canvas, then choose
**Path → Beztrace…**. The ordinary panel's **Trace** immediately appends native
paths; it becomes **Done**, and valid setting changes retrace inserted paths
with Undo. This is not a detached Prepare/Apply preview. Source images remain.
For review before any font write, use standalone output or `prepare_trace`
followed by a separately reviewed `apply_trace` in the loaded companion API.

Use one placement owner. Native tracing uses the canvas image's crop/affine
placement. Standalone JSON is neutral Y-up unless explicit placement is requested;
SVG owns its display conversion. Do not apply the transform or Y-flip twice.
Preserve advance widths, anchors, guides, existing paths and unrelated layers.
Trace application appends paths; replacement/deletion needs the requested scope.

## Deliver and verify

Return the vector artifact or apply through an available authorized consumer.
Check source evidence, engine/schema versions, finite closed paths, cubic
control ordering, counters/winding, bounds, counts and warnings. Revalidate
native targets and image placement before Apply. Saving, font creation,
installation and publication follow the user's task, not the act of tracing.

Report the image, placement and settings; total/on-curve counts; relevant
warnings; and what was visually or natively checked. If the purpose changes
to interpolation, route to master matching and verify correspondence.
