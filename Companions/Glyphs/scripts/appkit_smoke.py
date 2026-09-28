#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Isolated AppKit smoke check with a fake host; never connects to Glyphs.

Requires macOS, PyObjC/AppKit/Quartz, and WindowServer access. Native controls and
cached drawing run in this process. This is not visual or Glyphs qualification.
"""
import sys
from pathlib import Path
from types import SimpleNamespace as NS

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'),str(ROOT/'tests')]
# Only the callback constant is imported by the controller after host injection.
sys.modules['GlyphsApp'] = NS(DRAWFOREGROUND='drawForeground')
from AppKit import NSApplication, NSAppearance, NSImage, NSColor
from test_adapter import FakeHost
from test_inspector import metrics, letter
from test_contract import sample
from beztrace_companion import ui


class Host(FakeHost):
    def __init__(self):
        super().__init__()
        self.document = NS(displayName=lambda:'Disposable AppKit target')
        self.glyph = NS(name='A')
        self.owner.name = 'Regular'; self.owner.paths = []
        self.callbacks = []
        self.app = NS(addCallback=lambda *a:self.callbacks.append(a),
                      removeCallback=lambda fn:self.callbacks.clear())
        self.same = lambda a,b:a is b

    def metrics(self, owner): return metrics()
    def classification(self, glyph): return letter('A')


def run():
    ui.GlyphsHost = Host
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(2)
    controller = ui.BeztraceWindowController.alloc().init()
    try:
        assert controller.session.target and controller.fit.height == 700
        assert controller.window().isFloatingPanel()
        assert not controller.views['apply'].isEnabled()
        assert controller.preview.mode == 'Overlay'
        fixture = ROOT.parents[1]/'Tests/Fixtures/corpus/deterministic'
        image = fixture/'symbols/symbol-power.png'
        assert controller.load_image(image)
        token,_ = controller.session.begin(controller.session.target)
        controller.session.complete(token,sample())
        controller.update_preview()
        assert controller.views['apply'].isEnabled()
        assert controller.cached.geometry.paths is controller.placed
        assert len(controller.host.callbacks) == 1
        before = controller.host.fingerprint(controller.session.target.layer)
        for appearance in ('NSAppearanceNameAqua','NSAppearanceNameDarkAqua'):
            import AppKit
            controller.window().setAppearance_(NSAppearance.appearanceNamed_(getattr(AppKit,appearance)))
            canvas = NSImage.alloc().initWithSize_((1000,1000))
            canvas.lockFocus()
            try:
                NSColor.windowBackgroundColor().set()
                AppKit.NSBezierPath.fillRect_(((0,0),(1000,1000)))
                for zoom in (.25,1,4):
                    controller.beztraceInspectorDrawForeground(controller.host.owner,{'Scale':zoom})
                for mode in ('Image','Overlay','Outline'):
                    controller.preview.mode = mode
                    controller.preview.drawRect_(controller.preview.bounds())
            finally:
                canvas.unlockFocus()
        assert controller.overlay_fault is None, controller.overlay_fault
        assert controller.host.fingerprint(controller.session.target.layer) == before
        assert controller.host.undo == 0
        controller.fields['height'].setStringValue_('640')
        controller.controlTextDidChange_(NS(object=lambda:controller.fields['height']))
        assert controller.views['fit'].titleOfSelectedItem() == 'Custom'
        assert controller.fit.height == 640
        controller.toggleAdvanced_(None); controller.toggleText_(None)
        controller.status('Failure details','Long diagnostic.\n'*100)
        controller.toggleDetails_(None)
        for width,height in ((360,480),(400,680),(520,1100)):
            controller.window().setContentSize_((width,height)); controller.layout()
            assert controller.document.bounds().size.height >= controller.scroll.contentSize().height
            for key in ('trace','apply','details'):
                frame = controller.views[key].frame()
                assert frame.origin.x >= 0 and frame.origin.x+frame.size.width <= width
        controller.traceOptionChanged_(None)
        assert controller.cached is None and not controller.host.callbacks
        assert not controller.views['apply'].isEnabled()
        assert controller.views['trace'].title() == 'Retrace'
        controller.messages.put((token,'result',sample()))
        controller.poll_(None)
        assert controller.session.result is None
    finally:
        controller.windowWillClose_(None)
        controller.window().close()
    assert controller.session.closed and not controller.host.callbacks
    print('PASS: AppKit controls, presets, shared geometry, thumbnail modes, overlay drawing, '
          'light/dark API paths, zoom, layout bounds, stale results, and cleanup. '
          'No Glyphs process or font accessed. Visual/native Glyphs qualification remains pending.')


if __name__ == '__main__': run()
