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
from beztrace_companion.settings import TraceSettings


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
    real_trace=ui.trace; warning_trace={'enabled':False}
    def trace_with_warning(*args,**kwargs):
        result=real_trace(*args,**kwargs)
        if warning_trace['enabled']:
            result=dict(result); result['warnings']=['Grid 8 was skipped for 1 contour to preserve valid geometry.']
        return result
    ui.trace=trace_with_warning
    preferences={}
    ui.load_preferences=lambda: TraceSettings.from_persistent_value(preferences.get('settings'))
    def save(settings,advanced): preferences['settings']=settings.persistent_value(advanced)
    ui.save_preferences=save
    controller=ui.BeztraceWindowController.alloc().init()
    controller.engine=os.environ.get('BEZTRACE_TEST_ENGINE',controller.engine)
    try:
        controller.poll_(None)
        assert controller.window().contentView().bounds().size.width==300
        assert controller.window().contentView().bounds().size.height==210
        assert not controller.advanced and all(view.isHidden() for view in controller.advanced_views)
        assert not controller.preset.isHidden() and controller.threshold.isHidden()
        assert controller.preset.nextKeyView() is controller.invert
        assert controller.invert.nextKeyView() is controller.advanced_button
        assert controller.advanced_button.nextKeyView() is controller.trace_button
        assert controller.advanced_button.frame().origin.x>250
        assert controller.advanced_button.accessibilityValue()=='Collapsed'
        assert controller.accuracy_slider.accessibilityLabel()=='Accuracy'
        assert controller.smoothing_slider.accessibilityLabel()=='Smoothing'
        assert controller.grid.accessibilityLabel()=='Output grid'
        assert 'follow source pixels' in controller.accuracy_slider.accessibilityHelp()
        assert 'suppress raster corners' in controller.smoothing_slider.accessibilityHelp()
        assert 'before Glyphs placement' in controller.grid.accessibilityHelp()
        old=controller.window().frame(); old_top=old.origin.y+old.size.height
        controller.toggleAdvanced_(None)
        new=controller.window().frame()
        assert controller.window().contentView().bounds().size.height==410
        assert abs(new.origin.y+new.size.height-old_top)<1e-7
        visible=[view for view in controller.advanced_views if view not in (controller.value,controller.slider)]
        assert controller.advanced and all(not view.isHidden() for view in visible)
        assert controller.value.isHidden() and controller.slider.isHidden()
        assert controller.advanced_button.accessibilityValue()=='Expanded'
        assert controller.threshold_label.frame().origin.x==controller.preset_label.frame().origin.x==12
        assert controller.advanced_button.nextKeyView() is controller.threshold
        assert controller.threshold.nextKeyView() is controller.accuracy_slider
        assert controller.refine.nextKeyView() is controller.trace_button
        controller.preset.selectItemWithTitle_('Smooth Detail'); controller.presetChanged_(None)
        assert controller.options()['accuracy']==.75 and controller.options()['smoothing']==1.5
        selected=controller.options()
        assert selected['corner_threshold']==30 and selected['grid']==0,selected
        controller.accuracy_slider.setDoubleValue_(1.2); controller.advancedSliderChanged_(controller.accuracy_slider)
        assert controller.accuracy_value.stringValue()=='1.25'
        assert str(controller.preset.titleOfSelectedItem())=='Custom'
        controller.smoothing_slider.setDoubleValue_(.25)
        controller.advancedSliderChanged_(controller.smoothing_slider)
        assert controller.smoothing_value.stringValue()=='0.25'
        assert abs(controller.smoothing_slider.doubleValue()-.25)<1e-7
        controller.smoothing_value.setStringValue_('1.7'); controller.controlTextDidChange_(None)
        assert abs(controller.smoothing_slider.doubleValue()-1.7)<1e-7
        valid_top=controller.window().frame().origin.y+controller.window().frame().size.height
        controller.smoothing_value.setStringValue_('0.2'); controller.controlTextDidChange_(None)
        assert controller.retrace_at is None and not controller.validation_label.isHidden()
        assert controller.validation_control is controller.smoothing_value
        assert controller.validation_label.stringValue()=='Enter a value from 0.25 to 3.0.'
        assert controller.window().contentView().bounds().size.height==428
        frame=controller.window().frame()
        assert abs(frame.origin.y+frame.size.height-valid_top)<1e-7
        controller.controlTextDidEndEditing_(None)
        assert controller.smoothing_value.stringValue()=='1.7'
        assert controller.validation_label.isHidden()
        assert controller.window().contentView().bounds().size.height==410
        controller.resetSettings_(None)
        assert not controller.advanced and controller.trace_settings==TraceSettings()
        assert controller.window().contentView().bounds().size.height==210
        assert not controller.trace_button.isEnabled()
        assert not hasattr(controller,"image_button")
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
        assert controller.trace_button.title()=='Done'
        generation=controller.session.generation
        controller.toggleAdvanced_(None)
        controller.preset.selectItemWithTitle_('Sharp'); controller.presetChanged_(None)
        warning_trace['enabled']=True
        assert controller.session.generation==generation+1
        assert controller.retrace_at is not None
        deadline=time.monotonic()+20
        while (controller.retrace_at is not None or controller.session.busy) and time.monotonic()<deadline:
            time.sleep(.02); controller.poll_(None)
        assert controller.session.applied and len(controller.host.owner.shapes)==count,controller.details
        assert 'Grid 8 was skipped for 1 contour' in controller.status_label.stringValue()
        warning_trace['enabled']=False
        manual_top=controller.window().frame().origin.y+controller.window().frame().size.height
        controller.threshold.selectItemAtIndex_(1); controller.settingsChanged_(None)
        assert controller.window().contentView().bounds().size.height==434
        frame=controller.window().frame()
        assert abs(frame.origin.y+frame.size.height-manual_top)<1e-7
        assert not controller.slider.isHidden() and not controller.value.isHidden()
        assert controller.threshold.nextKeyView() is controller.slider
        assert controller.slider.nextKeyView() is controller.value
        stale=controller.session.generation
        controller.slider.setIntegerValue_(140); controller.sliderChanged_(None)
        controller.messages.put((stale,'result',None))  # Must be discarded before unpacking.
        assert controller.value.stringValue()=='140'
        deadline=time.monotonic()+20
        while (controller.retrace_at is not None or controller.session.busy) and time.monotonic()<deadline:
            time.sleep(.02); controller.poll_(None)
        assert controller.session.applied,controller.details
        assert len(controller.host.owner.shapes)==count
        assert controller.trace_button.title()=='Done'
        controller.value.setStringValue_('999'); controller.controlTextDidChange_(None)
        assert controller.retrace_at is None and not controller.session.busy
        assert controller.validation_control is controller.value
        assert controller.validation_label.stringValue()=='Enter a whole number from 0 to 255.'
        assert controller.window().contentView().bounds().size.height==452
        try: controller.options(); raise AssertionError('invalid threshold accepted')
        except CompanionError: pass
        controller.controlTextDidEndEditing_(None)
        assert controller.value.stringValue()=='140'
        assert controller.validation_label.isHidden()
        assert controller.window().contentView().bounds().size.height==434
        controller.value.setStringValue_('150'); controller.controlTextDidChange_(None)
        controller.host.owner.width=99
        deadline=time.monotonic()+2
        while controller.retrace_at is not None and time.monotonic()<deadline:
            time.sleep(.02); controller.poll_(None)
        assert 'destination changed' in controller.details
        assert controller.host.owner.width==99
        for appearance in ('NSAppearanceNameAqua','NSAppearanceNameDarkAqua'):
            import AppKit
            controller.window().setAppearance_(NSAppearance.appearanceNamed_(getattr(AppKit,appearance)))
        controller.preset.selectItemWithTitle_('Smooth Detail'); controller.presetChanged_(None)
        restored=ui.BeztraceWindowController.alloc().init()
        try:
            assert restored.advanced and restored.trace_settings.preset=='Smooth Detail'
            assert restored.window().contentView().bounds().size.height==434
        finally:
            restored.windowWillClose_(None); restored.window().close()
        controller.retrace_at=None
        controller.traceImage_(None)
        assert controller.session.closed and controller.pending is None
    finally:
        controller.windowWillClose_(None); controller.window().close()
    print('PASS: 300×210/410 AppKit panel, right disclosure, inline validation, presets, persistence, native image rasterization, real engine, deferred capture, '
          'automatic insertion through fake host, live replacement, stale context, cancellation, controls and cleanup. '
          'No Glyphs process or user font accessed.')


if __name__=='__main__': run()
