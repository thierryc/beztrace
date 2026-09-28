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
