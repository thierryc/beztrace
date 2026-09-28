# Glyphs 4 API evidence

The user-invoked glyphs-mcp-development skill supplied the offline SDK corpus at
revision `0f5422db727b78cb42abfb386f33ae0b382b0c4d`. The scaffold's loader checksum,
source URL, revision, and Apache license are retained in the bundle. No code was
copied from the Glyphs MCP bridge or sidecar.

| Adapter behavior | Pinned source evidence |
| --- | --- |
| GeneralPlugin startup and Path menu | `Python Templates/General Plugin/README.md`, menu constants and native NSMenuItem example |
| Native node constants | `ObjectWrapper/GlyphsApp/__init__.py`, `GSNode.type`, API section 447 |
| Node stream and closure | `GSPath.nodes` and `GSPath.closed`, sections 432 and 434 |
| Winding readback | `GSPath.direction`, section 435: -1 counterclockwise, +1 clockwise |
| Shapes including components | `GSLayer.shapes`, section 338; indexed deletion and shape assignment |
| Native recovery copy | `GSLayer.copy`, section 373 |
| Background access | `GSLayer.background`, section 358 and its wrapper implementation |
| Undo group | `GSGlyph.beginUndo` / `endUndo`, sections 319–320 |
| Ownership and identity | `GSLayer.parent`, section 324; `GSGlyph.id`, section 274; `GSFont.parent`, section 54; `Glyphs.documents`, section 4 |
| Cached edit-view drawing | `Glyphs.addCallback` / `removeCallback`, `DRAWFOREGROUND`; callback receives `layer` and `info["Scale"]` |
| Applicable layer metrics | `GSLayer.metrics`: filtered `GSMetricStore` list; `GSMetricStore.metric`, `.filter`, `.position` |
| Master metric fallback | `GSFont.metrics`, `GSMetric.type/id/filter`, `GSFontMaster.metrics` / `MasterMetricsProxy.getByKey`; metrics indexed by stable ID |
| Metric types | `GSMetricsTypeBaseline`, `GSMetricsTypeCapHeight`, `GSMetricsTypexHeight`, `GSMetricsTypeAscender`, `GSMetricsTypeDescender` |
| Conservative classification | `GSGlyph.name`, `.unicode`, `.category`, `.case`, `GSUppercase`, `GSLowercase` |
| Lock checks | `GSGlyph.locked`, `GSPath.locked`, wrapper properties |

Official source: [pinned GlyphsSDK](https://github.com/schriftgestalt/GlyphsSDK/tree/0f5422db727b78cb42abfb386f33ae0b382b0c4d).

`temporarilyDisableRounding` and `setTemporarilyDisableRounding_` are qualified
project evidence from the development skill's `references/native-precision.md`
for Glyphs 4.1 build 4107, not a universal SDK guarantee. The adapter checks both,
preserves their prior state, and verifies coordinates after restoration. An
unavailable selector fails before mutation.

Glyphs MCP status was read during planning: Glyphs 4.1 build 4107 was reachable.
That establishes host availability only. No plugin was installed or loaded and
no open font was accessed or changed in this implementation run. Native behavior
and background-owner resolution remain subject to the qualification checklist.

Build 2 retains the general-plugin scaffold and adds a uniquely named foreground
drawing function. It does not register a second reporter plugin. The AppKit panel
uses NSPanel, NSScrollView, native controls, and system colors; an isolated fake-host
smoke check exercises these APIs. Glyphs callback positioning, native metric-store
behavior, image alignment, and actual accessibility still require in-app testing.

## Optional native collections (build 3)

The pinned wrapper's `ListProxy.__iter__` and `__len__` call `iter(values())`
and `len(values())`. `LayerGuidesProxy.values`, `LayerAnnotationProxy.values`,
and `LayerHintsProxy.values` return the native getter directly; that getter may
return nil before the collection is allocated. Build 3 snapshots optional
collections through `.values()` and treats only an actual `None` as empty.
Unexpected native read failures still propagate. Regression tests reproduce the
SDK proxy semantics, including the failing iteration in build 2.

## Selection during AppKit actions (build 4)

The same pinned SDK defines `GSFont.selectedLayers` through its parent document,
`GSFont.currentTab` through the active edit controller, and
`GSEditViewController.selectedLayers` through the native method. In Glyphs 4.1
build 4107, a read-only diagnostic during the inspector's Use Current callback
returned an empty array from both selection APIs. A main-thread timer 0.1 seconds
later returned the selected layer and completed the existing `capture` routine,
including metrics and fingerprint reads. A delayed probe with the inspector still
key also saw the selection. This is qualified host behavior, not a general SDK
promise. Build 4 performs capture on the next inspector timer tick and checks
that the request's font, document, and active tab are still current and open.

## Native canvas images (build 5)

The pinned SDK documents `GSLayer.backgroundImage`, `GSBackgroundImage.path`,
`.image`, `.crop`, `.transform`, `.position`, `.scale`, `.rotation`, `.locked`,
and `.resetCrop()`. A native image uses a six-value affine transform; its NSImage
is read-only through that property. The crop text describes pixels, but the
wrapper's resetCrop uses `image.size()`. Glyphs 4.1/4107 native probes confirm
that a 160 × 180 raster at 144 DPI has logical size **80 × 90**, with the same
80 × 90 default crop and identity transform. The adapter therefore maps through
native logical size/crop rather than assuming pixels equal font units. An
EXIF-6 JPEG reports the oriented native size (180 × 160); native rasterization
and subsequent tracing preserve that orientation.

`scripts/native_canvas_probe.py` runs with the official Glyphs CLI and plugins
disabled. It verifies native image/path Undo/Redo, fractional readback, nine
transform cases, crop/DPI/EXIF, foreground/background preservation, and the
image-only placement API. It uses detached fonts and substitutes their ownership
check for document membership. This is backend qualification on build 4107,
not evidence that the updated menu/panel is loaded or that visible edit-view
alignment has been inspected. Build 5 registers no drawing callbacks.
