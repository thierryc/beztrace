# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Opt-in disposable native probe. Run only in an authorized Glyphs test session.

From the Glyphs 4 Scripting Window, import this file and call run(resources).
It creates and shows one NEW unsaved font. It never reads/modifies another font,
installs a plugin, saves a document, or restarts Glyphs. It leaves the fixture open
for manual Undo/Redo inspection. This is an adapter probe, not a plugin UI test.
"""
import sys


def run(resources):
    sys.path.insert(0,str(resources))
    from GlyphsApp import GSFont,GSFontMaster,GSGlyph
    from beztrace_companion.native import GlyphsHost
    from beztrace_companion.adapter import Target,apply_paths
    font=GSFont()
    font.familyName='Beztrace Disposable Qualification'
    master=GSFontMaster(); master.name='Regular'; font.masters.append(master)
    glyph=GSGlyph('A'); font.glyphs.append(glyph)
    layer=glyph.layers[master.id]; layer.width=600
    font.show()
    host=GlyphsHost()
    target=Target(font.parent,font,glyph,layer,layer,'foreground',host.identity(glyph,layer),
                  host.fingerprint(layer),host.label(font.parent,font,glyph,layer))
    nodes=[dict(x=50.25,y=-20.5,type='curve',smooth=False),
           dict(x=450.25,y=-20.5,type='line',smooth=False),
           dict(x=450.25,y=700.5,type='offcurve',smooth=False),
           dict(x=50.25,y=700.5,type='offcurve',smooth=False)]
    apply_paths(host,target,[dict(closed=True,nodes=nodes)])
    assert len(layer.paths)==1 and layer.width==600
    assert host.path_data(layer.paths[0])==dict(closed=True,nodes=nodes)
    font.newTab('/A')
    print('Native adapter probe passed coordinate readback; verify Undo/Redo manually.')
    return font
