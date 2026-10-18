#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Real AppKit matching panel with a read-only fake host; no Glyphs/font access."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import time
from types import SimpleNamespace as NS

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
sys.path[:0]=[str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'),str(ROOT/'tests')]


def run(output,hold,showcase,screen_capture=False):
    from AppKit import NSApplication,NSAppearance,NSBitmapImageFileTypePNG,NSImage
    from Foundation import NSDate,NSRunLoop,NSMakeRect
    from PIL import Image
    from test_matching import Host
    from beztrace_companion import matching_ui
    from beztrace_companion.matching_contract import MatchingDiagnosticError
    from beztrace_companion.contract import CompanionError
    from beztrace_companion.adapter import Target
    from beztrace_companion import image_io

    request=json.loads((REPO/'Tests/Fixtures/matching/v1/shifted-start.json').read_text())
    engine=Path(os.environ.get('BEZTRACE_MATCH_ENGINE',str(REPO/'.build/release/beztrace'))).resolve()
    assert engine.is_file(),'Build the matching engine before the native check'

    class ReadOnlyHost(Host):
        def __init__(self):
            super().__init__(dict(sourceMasters=[request['reference'],request['target']]))
            self.font=NS(masters=[NS(id='0',name='Light'),NS(id='1',name='Bold')])
            self.glyph=NS(name='smoke.fixture')
            self.selection=1
        def current_selection(self):
            return None,self.font,self.glyph,NS(layerId=str(self.selection),name=('Light','Bold')[self.selection]),'foreground'
        def context(self,font,glyph,reference_id):
            assert len(self.font.masters)==2,'Paired context used outside the two-master workflow'
            ctx=super().context(font,glyph,reference_id)
            if reference_id=='1':
                for key in ('targets','outlines','fingerprints'): ctx[key].reverse()
                ctx['axis']['locations'].reverse()
            return ctx
        def revalidate_match(self,ctx):
            expected=[self.fingerprint(t.layer) for t in ctx['targets']]
            if expected!=ctx['fingerprints']: raise CompanionError('stale target')
            from beztrace_companion.matching_raster import revalidate_sources
            revalidate_sources(self,ctx)
        def target(self,font,glyph,layer_id,destination='foreground'):
            index=int(layer_id); layer=self.layers[index]; layer.paths=layer.shapes
            return Target(None,font,self.glyph,NS(layerId=layer_id,name=('Light','Bold')[index]),layer,
                          destination,(glyph,layer_id),self.fingerprint(layer),glyph)
        def path_data(self,path): return copy.deepcopy(path)
        def contains(self,target): return any(target.layer is layer for layer in self.layers)
        def check_editable(self,*args): pass
        def same(self,a,b): return a is b
        def assert_main(self):
            from Foundation import NSThread
            assert NSThread.isMainThread(),'Native UI work left the main thread'
        def begin_undo(self,*args): raise AssertionError('Read-only UI check attempted Apply')
        def install_stage(self,*args): raise AssertionError('Read-only UI check attempted a write')
        def restore(self,*args): raise AssertionError('Read-only UI check attempted recovery')

    def pump(seconds=.04):
        NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(seconds))

    def prepare(controller):
        controller.prepare_button.performClick_(None)
        end=time.monotonic()+20
        while controller.job is not None and time.monotonic()<end: pump(.01)
        assert controller.job is None,'Panel preparation timed out'

    def capture(view,name):
        view.displayIfNeeded()
        bitmap=view.bitmapImageRepForCachingDisplayInRect_(view.bounds())
        assert bitmap is not None,'Native bitmap allocation failed'
        view.cacheDisplayInRect_toBitmapImageRep_(view.bounds(),bitmap)
        data=bitmap.representationUsingType_properties_(NSBitmapImageFileTypePNG,{})
        path=output/(name+'.png'); path.write_bytes(bytes(data))
        return path

    def inspector_layout(controller):
        bounds=controller.inspector_content.bounds()
        rows={name:views for name,_,views in controller.option_rows}
        previous=bounds.size.height
        keyboard=[]
        from AppKit import NSButton,NSPopUpButton,NSTextField
        for name in controller.visible_rows:
            views=rows[name]
            top=max(v.frame().origin.y+v.frame().size.height for v,_ in views)
            bottom=min(v.frame().origin.y for v,_ in views)
            assert 0<=bottom<top<=previous,'Inspector row overlaps or escapes its document: '+name
            previous=bottom
            for view,_ in views:
                assert not view.isHidden()
                frame=view.frame()
                assert frame.origin.x>=0 and frame.origin.x+frame.size.width<=bounds.size.width
                if isinstance(view,(NSButton,NSPopUpButton)) or isinstance(view,NSTextField) and view.isEditable():
                    keyboard.append(view)
        for first,second in zip(keyboard,keyboard[1:]):
            assert first.nextKeyView()==second,'Tab order differs from visible row order'

    def red_pixels(path):
        with Image.open(path) as image:
            image=image.convert('RGB'); width,height=image.size
            return {(x,y) for y in range(height) for x in range(width)
                    if (lambda c:c[0]>150 and c[0]>c[1]*1.7 and c[0]>c[2]*1.4)(image.getpixel((x,y)))},width

    def preserved(host,before):
        assert before==[host.fingerprint(layer) for layer in host.layers]
        assert not host.events,'Preview generated an Undo/write/redraw event'
        assert 'GlyphsApp' not in sys.modules,'Native font module was imported'

    app=NSApplication.sharedApplication(); app.setActivationPolicy_(1); app.finishLaunching()
    matching_ui.MatchingHost=ReadOnlyHost
    matching_ui.load_preferences=lambda:(matching_ui.TraceSettings(),False)
    matching_ui.save_preferences=lambda *args:None
    output.mkdir(parents=True,exist_ok=True)
    controller=matching_ui.MatchingWindowController.alloc().init(); controller.engine=str(engine)
    checks=[]; captures=[]; diagnostics=[]; rendering=[]
    def passed(name): checks.append(name); print('PASS:',name,flush=True)
    try:
        host=controller.host; before=[host.fingerprint(layer) for layer in host.layers]
        assert controller.ctx is not None,controller.details
        assert controller.window().contentView().bounds().size==(820,620)
        for button,icon,label in zip(controller.mode.options,controller.mode.icons,controller.mode.labels):
            assert button.isFlipped()
            assert icon.frame().origin.y+icon.frame().size.height<label.frame().origin.y
            assert icon.hitTest_((0,0)) is None and label.hitTest_((0,0)) is None
            assert button.accessibilityLabel() in matching_ui.MODE_LABELS
        assert controller.prepare_button.isEnabled() and not controller.apply_button.isEnabled()
        assert controller.target.indexOfSelectedItem()==host.selection
        assert controller.reference.indexOfSelectedItem()==0
        assert controller.primary_action=='process' and controller.prepare_button.keyEquivalent()==''
        assert controller.prepare_button.bezelColor() is None
        assert controller.slider.doubleValue()==50
        assert controller.window().defaultButtonCell() is None
        assert not controller.apply_button.isHidden() and not controller.prepare_button.isHidden()
        assert not controller.slider.isHidden() and not controller.slider.isEnabled()
        assert controller.inspector is not None
        assert controller.preview.bounds().size.width*controller.preview.bounds().size.height>=520*296
        assert controller.repair.isHidden() and not controller.repair.state()
        assert not controller.smooth.isHidden() and controller.smooth.state()
        assert controller.preview.accessibilityLabel()=='Glyph outline preview'
        assert controller.slider.accessibilityLabel()=='Interpolation axis'
        controller.showWindow_(None); controller.window().makeKeyAndOrderFront_(None); app.activateIgnoringOtherApps_(True); pump()
        assert controller.window().isVisible()
        passed('visible 820×620 panel, current master as target, secondary Update Preview')
        captures.append(capture(controller.content,'matching-basic-controls').name)
        assert not hasattr(controller,'advanced_button')
        assert not controller.policy.isHidden() and not controller.manual.isHidden()
        assert controller.threshold.isHidden() and controller.repair.isHidden()
        assert not controller.smooth.isHidden() and controller.settings()['smoothJoins']
        assert controller.extra_points.stringValue()=='0' and controller.fit.stringValue()=='1'
        assert controller.max_points.stringValue()=='5'
        for _,_,views in controller.option_rows:
            for view,_ in views:
                if not view.isHidden():
                    frame=view.frame(); bounds=controller.inspector_content.bounds()
                    assert frame.origin.y>=0 and frame.origin.y+frame.size.height<=bounds.size.height
        passed('Grouped inspector hides irrelevant controls; unchanged tolerance and node limits')
        original=controller.settings()
        controller.manual.setState_(1); controller.settingsChanged_(None)
        assert not controller.contour.isHidden() and controller.settings()==original
        controller.pairs=[0]; controller.starts=[0]
        assert controller.settings()['contourPairs']==[0]
        controller.manual.setState_(0); controller.settingsChanged_(None)
        assert controller.settings()['contourPairs']==[] and controller.settings()['startNodes']==[]
        controller.reset_pairs()
        controller.policy.selectItemAtIndex_(1); controller.settingsChanged_(None)
        assert not controller.extra_points.isHidden()
        controller.hoi_available=True; controller.repair.setState_(1); controller.layout_options()
        assert not controller.kink.isHidden() and not controller.movement.isHidden()
        controller.manual.setState_(1); controller.layout_options(); pump()
        inspector_layout(controller)
        captures.append(capture(controller.content,'matching-expanded-controls').name)
        controller.inspector.contentView().scrollToPoint_((0,0)); pump()
        captures.append(capture(controller.content,'matching-expanded-bottom').name)
        controller.review.setState_(1); controller.settingsChanged_(None)
        assert controller.manual.isHidden() and controller.contour.isHidden() and controller.extra_points.isHidden()
        controller.review.setState_(0); controller.manual.setState_(0)
        controller.hoi_available=False; controller.repair.setState_(0)
        controller.policy.selectItemAtIndex_(0); controller.settingsChanged_(None)
        assert controller.settings()==original
        passed('Manual, shared-growth and native HOI fields appear only when selected; review omits overrides')
        prepare(controller)
        assert controller.plan is not None and controller.apply_button.isEnabled(),controller.details
        assert controller.plan.result['jointSmoothing']['sampleCount']==201
        reviewed=controller.plan
        controller.manual.setState_(1); controller.settingsChanged_(None)
        assert controller.plan is reviewed and controller.apply_button.isEnabled()
        controller.manual.setState_(0); controller.settingsChanged_(None)
        assert controller.plan is reviewed and controller.apply_button.isEnabled()
        controller.smooth.setState_(0); controller.settingsChanged_(None)
        assert not controller.apply_button.isEnabled() and controller.preview.cache is not None
        prepare(controller)
        assert 'jointSmoothing' not in controller.plan.result
        controller.smooth.setState_(1); controller.settingsChanged_(None)
        assert not controller.apply_button.isEnabled()
        prepare(controller)
        assert controller.plan.result['jointSmoothing']['sampleCount']==201
        passed('Smooth compatible joins invalidates Apply, preserves the preview and routes only the requested verified operation')
        controller.imported=b'imported geometry'; controller.buttons()
        assert not controller.smooth.isEnabled()
        controller.imported=None; controller.buttons()
        assert controller.smooth.isEnabled() and controller.apply_button.isEnabled()
        passed('Imported geometry keeps its smoothing choice read-only')
        assert controller.primary_action=='apply' and controller.apply_button.keyEquivalent()=='\r'
        assert controller.apply_button.bezelColor() is not None
        assert controller.window().defaultButtonCell()==controller.apply_button.cell()
        assert not controller.prepare_button.isHidden() and not controller.prepare_button.isEnabled() and not controller.apply_button.isHidden()
        assert controller.inspector is not None
        assert not controller.slider.isHidden() and controller.slider.isEnabled()
        assert controller.preview.cache['links'] and not controller.preview.cache['diagnosticHighlights']
        for factor,location in ((0,100),(50,500),(100,900)):
            controller.slider.setDoubleValue_(factor); controller.sliderChanged_(None)
            assert controller.position_label.stringValue()=='%d%%'%factor
            assert controller.position_label.toolTip()=='wght %d'%location
            preserved(host,before)
        captures.append(capture(controller.content,'matching-ready').name)
        # A hint-only Apply refusal must retain the reviewed preview and slider.
        from unittest.mock import patch
        from beztrace_companion.matching_hints import HintMappingError
        reviewed=controller.plan; shown=controller.display_result
        def blocked_apply(plan):
            plan.apply_error='Apply blocked: a hint attachment cannot be mapped safely.'
            raise HintMappingError(plan.apply_error)
        with patch.object(matching_ui,'apply_match',side_effect=blocked_apply):
            controller.apply_button.performClick_(None)
        assert controller.plan is reviewed and controller.display_result is shown
        assert controller.preview.cache['processed'] and controller.slider.isEnabled()
        assert not controller.apply_button.isEnabled() and not controller.prepare_button.isEnabled()
        assert 'hint attachment' in controller.status.stringValue()
        controller.slider.setDoubleValue_(25); controller.sliderChanged_(None)
        assert controller.position_label.toolTip()=='wght 300'
        preserved(host,before)
        passed('hint Apply refusal retains reviewed preview and interpolation without source writes')
        controller.invalidate(); controller.set_status(''); prepare(controller)
        controller.settingsChanged_(None)
        assert controller.apply_button.isEnabled() and not controller.prepare_button.isEnabled()
        for style in (0,1,2):
            controller.preview_tabs.setSelectedSegment_(style); controller.previewStyleChanged_(None)
            assert controller.apply_button.isEnabled() and not controller.prepare_button.isEnabled()
            captures.append(capture(controller.preview,'preview-style-'+str(style)).name)
        controller.preview_tabs.setSelectedSegment_(0); controller.previewStyleChanged_(None)
        controller.fit.setStringValue_(str(float(controller.fit.stringValue())+.25)); controller.controlTextDidChange_(None)
        assert controller.primary_action=='process' and not controller.apply_button.isEnabled()
        assert controller.prepare_button.title()=='Update Preview' and controller.preview.cache['processed']
        assert not controller.slider.isHidden()
        prepare(controller); assert controller.plan is not None,controller.details
        passed('Process → Apply → changed options → Process again → Apply without source writes')
        controller.reference.selectItemAtIndex_(1); controller.referenceChanged_(None)
        assert controller.ctx['targets'][0].owner.layerId=='1'
        assert controller.target.indexOfSelectedItem()==0 and not controller.apply_button.isEnabled()
        controller.slider.setDoubleValue_(0); controller.sliderChanged_(None)
        assert controller.position_label.stringValue()=='0%'
        assert controller.position_label.toolTip()=='wght 100'
        prepare(controller); assert controller.plan is not None,controller.details
        # Return from a midpoint to both active masters, including shifted raw
        # starts. Context remains usable and processing remains available.
        for selected in (0,1):
            controller.slider.setDoubleValue_(50); controller.sliderChanged_(None)
            host.selection=selected; controller.useSelection_(None)
            assert controller.ctx is not None and controller.target.indexOfSelectedItem()==selected,controller.details
            assert controller.primary_action=='process' and controller.prepare_button.isEnabled()
            assert controller.slider.doubleValue()==50 and not controller.preview.cache['processed']
            prepare(controller); assert controller.plan is not None,controller.details
        preserved(host,before)
        passed('real-engine Process, midpoint rebinding in either direction, reversed reference, detached preservation')
        controller.invalidate()
        assert controller.plan is None and not controller.apply_button.isEnabled()
        preserved(host,before)
        passed('Cancel discards preview without writes')

        controller.max_points.setStringValue_('3'); controller.controlTextDidChange_(None)
        prepare(controller)
        assert controller.plan is None and not controller.apply_button.isEnabled()
        assert 'Point budget exceeded' in controller.status.stringValue(),controller.details
        assert controller.max_points.stringValue()=='3' and float(controller.fit.stringValue())==1.25
        assert controller.primary_action=='process' and controller.prepare_button.keyEquivalent()==''
        controller.max_points.setStringValue_('5'); controller.controlTextDidChange_(None)
        preserved(host,before)
        passed('Point-budget refusal preserves limits and offers Process again with Apply disabled')

        host.layers[1].shapes=[]; before=[host.fingerprint(layer) for layer in host.layers]
        controller.useSelection_(None)
        assert controller.primary_action=='unavailable' and not controller.prepare_button.isEnabled()
        assert not controller.prepare_button.keyEquivalent()
        controller.mode.setSelectedSegment_(2); controller.modeChanged_(controller.mode)
        assert controller.primary_action=='unavailable' and not controller.threshold.isHidden()
        controller.mode.setSelectedSegment_(3); controller.modeChanged_(controller.mode)
        assert controller.primary_action=='unavailable' and controller.threshold.isHidden()
        preserved(host,before)
        passed('Empty target has no primary action; image options appear only for image modes')

        # Exercise all four UI routes with real native raster snapshots and the real engine.
        from PIL import ImageDraw
        image_path=output/'rectangle.png'
        raster=Image.new('RGB',(256,256),'white')
        ImageDraw.Draw(raster).rectangle((64,28,191,227),fill='black'); raster.save(image_path)
        native_image=NSImage.alloc().initWithContentsOfFile_(str(image_path)); native_image.setSize_((256,256))
        for layer,source in zip(host.layers,(request['reference'],request['target'])):
            layer.shapes=copy.deepcopy(source['outline']['contours'])
            layer.backgroundImage=NS(path=str(image_path),image=native_image,crop=NSMakeRect(0,0,256,256),transform=(100/128,0,0,1,-50,-28))
        before=[host.fingerprint(layer) for layer in host.layers]
        for mode in (0,1,2,3):
            controller.mode.options[mode].performClick_(None)
            assert controller.ctx is not None,controller.details
            assert controller.prepare_button.isEnabled(),controller.status.stringValue()
            assert not controller.prepare_button.keyEquivalent() and controller.prepare_button.bezelColor() is None
            assert controller.reference.isHidden()==(mode==0)
            assert controller.fit.isHidden()==(mode==0)
            assert controller.max_points.isHidden()==(mode==0)
            assert controller.preset.isHidden()==(mode!=0)
            assert controller.threshold.isHidden()==(mode==3)
            assert controller.accuracy.isHidden()==(mode!=0)
            assert controller.policy.isHidden()==(mode not in (2,3))
            assert not controller.more_button.isHidden()
            controller.fit.setStringValue_('2'); controller.settingsChanged_(None)
            prepare(controller)
            assert controller.plan is not None,controller.details
            assert controller.apply_button.isEnabled(),controller.details
            assert not controller.prepare_button.isEnabled()
            reviewed=controller.plan; controller.mode.options[mode].performClick_(None)
            assert controller.plan is reviewed and not controller.prepare_button.isEnabled()
            inspector_layout(controller)
            assert controller.inspector_content.bounds().size.height==388
            captures.append(capture(controller.content,'mode-'+str(mode)+'-ready').name)
            field=controller.accuracy if mode==0 else controller.fit
            field.setStringValue_('1.5'); controller.controlTextDidChange_(None)
            assert controller.prepare_button.isEnabled() and not controller.apply_button.isEnabled()
            assert controller.preview.cache['processed']  # last preview stays visible
            assert controller.status.stringValue()==''  # no redundant stale message
            captures.append(capture(controller.content,'mode-'+str(mode)+'-dirty').name)
            prepare(controller); assert controller.plan is not None,controller.details
            preserved(host,before)
        passed('all four modes: real detached image/vector preparation, relevant settings, secondary dirty action')
        masters=host.font.masters
        host.font.masters=[masters[host.selection]]
        controller.mode.setSelectedSegment_(0); controller.modeChanged_(None)
        assert controller.ctx is not None,controller.details
        prepare(controller); assert controller.plan is not None,controller.details
        assert controller.apply_button.title()=='Apply to Layer' and controller.apply_button.isEnabled()
        preserved(host,before)
        host.font.masters=masters
        controller.mode.setSelectedSegment_(3); controller.modeChanged_(None)
        passed('Single image works in a one-master font without a matching context')
        controller.invalidate(); controller.prepare_(None)
        cancelled_job=controller.job
        assert cancelled_job is not None
        controller.cancel_(None); pump(.08)
        assert controller.job is None and controller.plan is None and not controller.closed
        assert not controller.apply_button.isEnabled() and controller.prepare_button.isEnabled()
        preserved(host,before)
        passed('Cancel stops an active preview; late completion does not enable Apply')
        # The panel also catches edits outside its own settings before Apply.
        host.layers[1].width=123
        controller.next_source_check=0; controller.poll_(None)
        assert not controller.apply_button.isEnabled() and controller.prepare_button.isEnabled()
        host.layers[1].width=0
        for layer in host.layers: layer.backgroundImage=None
        controller.useSelection_(None)
        before=[host.fingerprint(layer) for layer in host.layers]
        passed('external layer edits invalidate Apply without writing to the font')

        # A real refused crossing, offset from the source rectangle, has an
        # analytical intersection; unequal lobes avoid a prior zero-area refusal.
        # Native red pixels must remain in the source half.
        crossing=dict(closed=True,nodes=[dict(x=x,y=y,type='line',smooth=False)
            for x,y in ((20,20),(120,220),(20,220),(100,20))])
        intersection=(20+400/9,20+800/9)
        cubic=copy.deepcopy(crossing); cubic['nodes']=[]
        for i,node in enumerate(crossing['nodes']):
            if i in (1,3):
                start=crossing['nodes'][i-1]
                for factor in (1/3,2/3):
                    cubic['nodes'].append(dict(x=start['x']+(node['x']-start['x'])*factor,
                        y=start['y']+(node['y']-start['y'])*factor,type='offcurve',smooth=False))
            cubic['nodes'].append(dict(node,type='curve' if i in (1,3) else 'line'))
        for role,index,shape,kind in (('reference',0,crossing,'line'),('target',1,crossing,'line'),
                                     ('reference',0,cubic,'cubic'),('target',1,cubic,'cubic')):
            host.selection=1
            for layer,source in zip(host.layers,(request['reference'],request['target'])):
                layer.shapes=copy.deepcopy(source['outline']['contours'])
            host.layers[index].shapes=[copy.deepcopy(shape)]
            before=[host.fingerprint(layer) for layer in host.layers]
            controller.useSelection_(None); prepare(controller)
            diagnostic=controller.diagnostic
            assert controller.plan is None and not controller.apply_button.isEnabled()
            assert not controller.export_button.isEnabled()
            assert diagnostic is not None,controller.details
            assert diagnostic['stage']=='input' and diagnostic['role']==role,controller.details
            assert diagnostic['masterID']==str(index) and diagnostic['existedBeforeFitting']
            assert all(abs(a-b)<1e-10 for a,b in zip(diagnostic['coordinates'],intersection)),diagnostic
            assert len(diagnostic['locations'])==2
            assert [(p['segment'],p['startNode'],p['endNode']) for p in diagnostic['locations']]==(
                [(0,0,1),(2,2,3)] if kind=='line' else [(0,0,3),(2,4,7)])
            assert len(controller.preview.cache['diagnosticHighlights'])==4
            assert [command for command,values in controller.preview.cache['diagnosticHighlights']]==['M','L' if kind=='line' else 'C']*2
            assert controller.preview.cache['diagnosticMarkers']==[tuple(diagnostic['coordinates'])]
            assert '"locations"' in controller.details and '"startNode"' in controller.details
            diagnostics.append(copy.deepcopy(diagnostic))
            for appearance in ('Aqua','DarkAqua'):
                controller.window().setAppearance_(NSAppearance.appearanceNamed_('NSAppearanceName'+appearance)); pump()
                name=role+'-'+kind+'-'+appearance
                highlighted=capture(controller.preview,name+'-highlights')
                captures.append(highlighted.name)
                saved=controller.preview.cache
                controller.preview.cache=dict(saved,diagnosticHighlights=[],diagnosticMarkers=[])
                controller.preview.setNeedsDisplay_(True)
                plain=capture(controller.preview,name+'-plain')
                controller.preview.cache=saved; controller.preview.setNeedsDisplay_(True)
                red,width=red_pixels(highlighted); baseline,_=red_pixels(plain)
                added=red-baseline
                assert len(added)>300,(role,appearance,len(added))
                rendering.append(dict(role=role,kind=kind,appearance=appearance,
                    addedRedPixels=len(added),sourceGeometryOnly=True))
                # A marker near the reported crossing and red pixels on both
                # diagonals substantiate native drawing, not merely cached data.
                x0,y0,x1,y1=saved['bounds']
                scale=min((controller.preview.bounds().size.width-40)/max(1,x1-x0),
                          (controller.preview.bounds().size.height-40)/max(1,y1-y0))
                raster_scale=width/controller.preview.bounds().size.width
                with Image.open(highlighted) as image: height=image.height
                for x,y in (intersection,(45,70),(40,170)):
                    px=((controller.preview.bounds().size.width-max(1,x1-x0)*scale)/2+(x-x0)*scale)*raster_scale
                    py=height-((controller.preview.bounds().size.height-max(1,y1-y0)*scale)/2+(y-y0)*scale)*raster_scale
                    assert any(abs(a-px)<6*raster_scale and abs(b-py)<6*raster_scale for a,b in added), (role,appearance,x,y)
            preserved(host,before)
            controller.fit.setStringValue_(str(float(controller.fit.stringValue())+.25)); controller.controlTextDidChange_(None)
            assert controller.diagnostic is None and not controller.preview.cache['diagnosticHighlights']
            assert not controller.preview.cache['diagnosticMarkers'] and not controller.apply_button.isEnabled()
            passed(role+' '+kind+' refusal: source IDs, details, red segments/marker in light and dark, invalidation')

        fitted=dict(diagnostics[0],stage='fitted',existedBeforeFitting=False)
        controller.failure(MatchingDiagnosticError('Synthetic fitted-stage refusal',fitted))
        assert not controller.preview.cache['diagnosticHighlights'] and not controller.preview.cache['diagnosticMarkers']
        preserved(host,before)
        passed('fitted refusal does not display rejected geometry or enable Apply')
        # Leave the real reference refusal visible for optional screen inspection.
        host.layers[0].shapes=[copy.deepcopy(crossing)]
        host.layers[1].shapes=copy.deepcopy(request['target']['outline']['contours'])
        before=[host.fingerprint(layer) for layer in host.layers]
        controller.window().setAppearance_(NSAppearance.appearanceNamed_('NSAppearanceNameAqua'))
        controller.useSelection_(None); prepare(controller); pump()
        if showcase!='rejection':
            host.selection=1
            for layer,source in zip(host.layers,(request['reference'],request['target'])):
                layer.shapes=copy.deepcopy(source['outline']['contours'])
            before=[host.fingerprint(layer) for layer in host.layers]
            controller.useSelection_(None)
            if showcase=='apply':
                prepare(controller); controller.slider.setDoubleValue_(50); controller.sliderChanged_(None)
            elif showcase=='options': controller.layout_options()
            pump()
        if showcase=='images':
            for index,weight in enumerate(('regular','bold')):
                fixture=REPO/'Tests/Fixtures/matching/pair-v1'/('R-'+weight)
                host.layers[index].shapes=[]
                image_path=fixture.with_suffix('.png')
                with Image.open(image_path) as raster: width,height=raster.size
                native=NSImage.alloc().initWithContentsOfFile_(str(image_path)); native.setSize_((width,height))
                affine=json.loads(fixture.with_suffix('.transform.json').read_text())
                native_affine=tuple(v*1088/height for v in affine[:4])+tuple(affine[4:])
                host.layers[index].backgroundImage=NS(path=str(image_path),image=native,
                    crop=NSMakeRect(0,0,width,height),transform=native_affine)
            before=[host.fingerprint(layer) for layer in host.layers]
            controller.mode.setSelectedSegment_(1); controller.modeChanged_(None)
            controller.fit.setStringValue_('1'); controller.settingsChanged_(None)
            prepare(controller); assert controller.plan is not None,controller.details
            controller.fit.setStringValue_('1.5'); controller.settingsChanged_(None)
            assert controller.prepare_button.isEnabled() and not controller.apply_button.isEnabled()
        controller.layout_options(); pump()
        captures.append(capture(controller.content,'matching-final-panel').name)
        (output/'window.json').write_text(json.dumps(dict(windowID=controller.window().windowNumber(),pid=os.getpid())))
        if screen_capture:
            import subprocess,tempfile
            screenshot=Path(tempfile.gettempdir())/'beztrace-spacing-window.png'
            subprocess.run(['/usr/sbin/screencapture','-x','-l'+str(controller.window().windowNumber()),str(screenshot)],check=True)
            print('SCREENSHOT:',screenshot,flush=True)
        end=time.monotonic()+hold
        while time.monotonic()<end: pump(.1)
        preserved(host,before)
        from unittest.mock import patch
        with patch.object(host,'current_selection',side_effect=CompanionError('Select a glyph')):
            controller.useSelection_(None)
        assert controller.ctx is None and controller.preview.cache is None
        assert controller.primary_action=='unavailable' and not controller.prepare_button.isEnabled()
        assert not controller.apply_button.isEnabled()
        preserved(host,before)
        passed('Missing selection clears stale preview and disables both actions')
    finally:
        timer=controller.timer
        controller.windowWillClose_(None); controller.window().close()
        assert controller.closed and controller.timer is None and not timer.isValid()
        assert not controller.window().isVisible()
    passed('window close cancels state, invalidates timer and closes owned window')
    saved=[]
    stored=matching_ui.TraceSettings(threshold=135,accuracy=1.25,smoothing=1.1,grid=0,min_contour_area=4.)
    matching_ui.load_preferences=lambda:(stored,True)
    matching_ui.save_preferences=lambda settings,advanced:saved.append((settings,advanced))
    preference_controller=matching_ui.MatchingWindowController.alloc().init()
    try:
        preference_controller.mode.setSelectedSegment_(0); preference_controller.modeChanged_(None)
        assert not preference_controller.accuracy.isHidden()
        assert not hasattr(preference_controller,'advanced_button')
        assert preference_controller.trace_options()==stored.engine_options()
        preference_controller.threshold.setStringValue_('136')
        preference_controller.settingsChanged_(None)
        assert len(saved)==1 and saved[0][0].threshold==136 and saved[0][1] is True
        preference_controller.cancel_(None)
        assert preference_controller.closed
    finally:
        if not preference_controller.closed:
            preference_controller.windowWillClose_(None); preference_controller.window().close()
    passed('saved single-image settings survive the unified dialog; idle Cancel closes it')
    report=dict(checks=checks,captures=captures,diagnostics=diagnostics,rendering=rendering,
        nativeAppKit=True,visiblePanel=True,host='read-only fake host',glyphsProcessAccessed=False,
        fontFilesAccessed=False,fontMutation=False,installedGlyphsQualification=False,
        python=sys.version,macOS=platform.mac_ver()[0],architecture=platform.machine(),
        engine=str(engine),engineSHA256=hashlib.sha256(engine.read_bytes()).hexdigest(),
        moduleSHA256={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT/'Beztrace.glyphsPlugin/Contents/Resources/beztrace_companion').glob('matching*.py'))})
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: matching panel and native source highlights; no Glyphs process or font files accessed.',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-worker',action='store_true',help=argparse.SUPPRESS)
    parser.add_argument('--output',type=Path,default=REPO/'.build/glyphs-appkit-matching')
    parser.add_argument('--screen-capture',action='store_true',help='Capture the owned test window; requires screen-recording access')
    parser.add_argument('--hold',type=float,default=0.,help='Keep the owned panel visible for up to 60 seconds')
    parser.add_argument('--showcase',choices=('process','apply','options','rejection','images'),default='rejection')
    arguments=parser.parse_args()
    if not 0<=arguments.hold<=60: parser.error('--hold must be between 0 and 60 seconds')
    # A failed retry must not leave an earlier run's successful report in place.
    (arguments.output/'report.json').unlink(missing_ok=True)
    if arguments.native_worker: run(arguments.output,arguments.hold,arguments.showcase,arguments.screen_capture)
    else:
        from appkit_smoke_runner import run_native
        raise SystemExit(run_native(__file__,sys.argv[1:]))
