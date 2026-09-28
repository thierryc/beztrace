#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Isolated native controls/image renderer with fake font objects. No Glyphs access."""
import sys
import os
import time
from pathlib import Path
from types import SimpleNamespace as NS
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'),str(ROOT/'tests')]
from AppKit import NSApplication,NSImage,NSMakeRect,NSAppearance
from test_adapter import FakeHost
from beztrace_companion import ui,image_io
from beztrace_companion.adapter import Target
from beztrace_companion.contract import CompanionError


class Host(FakeHost):
    def __init__(self):
        super().__init__()
        self.document=NS(displayName=lambda:'Disposable AppKit target')
        self.glyph=NS(name='A'); self.owner.name='Regular'; self.owner.backgroundImage=None
        self.same=lambda a,b:a is b
        self.available=True
    def active_target(self):
        if not self.available: raise CompanionError('Select one glyph layer')
        return Target(self.document,self.font,self.glyph,self.owner,self.owner,'foreground',self.ids,self.fingerprint(self.owner),'Disposable / A / Regular')
    def selection_context(self): return self.document
    def check_selection_context(self,context):
        if context is not self.document: raise CompanionError('Document changed')
    def new_image(self,path):
        image=NSImage.alloc().initWithContentsOfFile_(str(path)); size=image.size()
        return NS(path=str(path),image=image,crop=NSMakeRect(0,0,size.width,size.height),transform=(1.,0.,0.,1.,30.,-20.),alpha=50,locked=False)
    def fingerprint(self,layer): return (FakeHost.fingerprint(self,layer),self.image_state(layer.backgroundImage))
    def snapshot(self,layer): return FakeHost.fingerprint(self,layer)
    def image_state(self,image): return (image.path,image.transform,image.crop) if image else None
    def content_without_image(self,layer): return FakeHost.fingerprint(self,layer)
    def set_image(self,layer,image): layer.backgroundImage=image


def run():
    app=NSApplication.sharedApplication(); app.setActivationPolicy_(2)
    ui.GlyphsHost=Host
    controller=ui.BeztraceWindowController.alloc().init()
    controller.engine=os.environ.get('BEZTRACE_TEST_ENGINE',controller.engine)
    try:
        controller.poll_(None)
        assert controller.window().contentView().bounds().size.width==280
        assert controller.window().contentView().bounds().size.height==190
        assert not controller.trace_button.isEnabled() and controller.image_button.isEnabled()
        image=ROOT.parents[1]/'Tests/Fixtures/corpus/deterministic/symbols/symbol-power.png'
        controller.host.owner.backgroundImage=controller.host.new_image(image)
        controller.next_refresh=0; controller.poll_(None)
        assert controller.trace_button.isEnabled()
        # Current layer cannot be read during the action; capture waits for poll.
        controller.host.available=False
        controller.traceImage_(None)
        assert controller.pending and not controller.session.busy
        controller.host.available=True; controller.poll_(None)
        assert controller.session.busy and controller.trace_button.title()=='Cancel'
        deadline=time.monotonic()+20
        while controller.session.busy and time.monotonic()<deadline:
            time.sleep(.02); controller.poll_(None)
        assert controller.session.applied,controller.details
        assert len(controller.host.owner.shapes)>2 and controller.host.owner.width==0
        assert controller.host.undo==0
        count=len(controller.host.owner.shapes)
        controller.traceImage_(None); controller.poll_(None)
        assert 'Already traced' in controller.details
        assert len(controller.host.owner.shapes)==count
        controller.traceImage_(None); controller.host.document=object(); controller.poll_(None)
        assert 'Document changed' in controller.details
        controller.threshold.selectItemAtIndex_(1); controller.settingsChanged_(None)
        controller.value.setStringValue_('999')
        try: controller.options(); raise AssertionError('invalid threshold accepted')
        except CompanionError: pass
        for appearance in ('NSAppearanceNameAqua','NSAppearanceNameDarkAqua'):
            import AppKit
            controller.window().setAppearance_(NSAppearance.appearanceNamed_(getattr(AppKit,appearance)))
        controller.traceImage_(None); controller.traceImage_(None)
        assert controller.pending is None and not controller.session.busy
        controller.traceImage_(None); controller.windowWillClose_(None); controller.poll_(None)
        assert controller.session.closed and controller.pending is None
    finally:
        controller.windowWillClose_(None); controller.window().close()
    print('PASS: 280×190 AppKit panel, native image rasterization, real engine, deferred capture, '
          'automatic insertion through fake host, duplicates, stale context, cancellation, controls and cleanup. '
          'No Glyphs process or user font accessed.')


if __name__=='__main__': run()
