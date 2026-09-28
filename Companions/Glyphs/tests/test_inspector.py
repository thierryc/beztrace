# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
from pathlib import Path
from types import SimpleNamespace as NS
import unittest
from test_contract import sample, contour
from test_adapter import FakeHost
from beztrace_companion.contract import CompanionError, place, signed_area
from beztrace_companion.placement import GlyphClass, metric_snapshot, resolve, auto_mode
from beztrace_companion.preview import geometry, OverlayBinding
from beztrace_companion.inspector import actions, mode_after_edit, accepts_image
from beztrace_companion.session import Session
from beztrace_companion.adapter import capture, revalidate, apply_paths
from beztrace_companion.native import GlyphsHost


def metrics(**overrides):
    values=dict(baseline=0,capHeight=700,xHeight=500,ascender=800,descender=-200)
    values.update(overrides)
    return metric_snapshot({},values)


def letter(char):
    return GlyphClass(char,'%04X' % ord(char),'upper' if char.isupper() else 'lower','Letter')


class PlacementPresetTests(unittest.TestCase):
    def test_supported_uppercase(self):
        for char in 'ABCDEFGHIKLMNOPRSTUVWXYZ':
            self.assertEqual(resolve('Auto',letter(char),metrics()).height,700)

    def test_supported_lowercase(self):
        for char in 'acemnorsuvwxz':
            self.assertEqual(resolve('Auto',letter(char),metrics()).height,500)

    def test_ambiguous_cases_require_explicit_choice(self):
        for char in 'JQbdfghijklpqtyéÁ0123456789!?Α':
            with self.subTest(char=char):
                with self.assertRaises(CompanionError): resolve('Auto',letter(char),metrics())
        for glyph in [GlyphClass('A.alt','0041','upper','Letter'),GlyphClass('Aacute','00C1','upper','Letter'),
                      GlyphClass('a','0061','upper','Letter'),GlyphClass('a','0061','lower','Symbol')]:
            with self.assertRaises(CompanionError): auto_mode(glyph)

    def test_explicit_lining_figures(self):
        for name in ['zero.lf','nine.lnum','4.lf']:
            fit=resolve('Auto',GlyphClass(name,category='Number'),metrics())
            self.assertEqual(fit.height,700)
            self.assertIn('fallback',fit.explanation)
        for name in ['zero','zero.osf','zero.tf','one.lf.alt','thing.lf']:
            with self.assertRaises(CompanionError): auto_mode(GlyphClass(name,category='Number'))

    def test_all_presets_and_nonzero_baseline(self):
        m=metrics(baseline=10)
        for mode,bottom,height in [('Cap height',10,690),('x-height',10,490),('Ascender',10,790),('Descender',-200,700)]:
            fit=resolve(mode,letter('q'),m)
            self.assertEqual((fit.bottom,fit.height),(bottom,height))

    def test_custom_does_not_require_metrics(self):
        fit=resolve('Custom',letter('é'),metric_snapshot({},{}),640,-140)
        self.assertEqual((fit.height,fit.bottom),(640,-140))

    def test_layer_specific_values_override_master(self):
        m=metric_snapshot({'capHeight':[(720,False),(680,True)]},dict(metrics().values))
        self.assertEqual(m.get('capHeight'),680)
        self.assertEqual(m.get('xHeight'),500)
        self.assertEqual(resolve('Auto',letter('A'),m).height,680)

    def test_conflicting_specific_metrics_do_not_guess(self):
        m=metric_snapshot({'capHeight':[(680,True),(690,True)]},dict(metrics().values))
        self.assertIsNone(m.get('capHeight'))
        with self.assertRaises(CompanionError): resolve('Cap height',letter('A'),m)
        self.assertEqual(resolve('x-height',letter('a'),m).height,500)

    def test_invalid_layer_metric_does_not_fall_back(self):
        for value in [None,True,float('nan'),float('inf')]:
            m=metric_snapshot({'capHeight':[(value,False)]},dict(metrics().values))
            with self.assertRaises(CompanionError): resolve('Cap height',letter('A'),m)

    def test_missing_inverted_and_excessive_ranges(self):
        for m in [metrics(capHeight=None),metrics(capHeight=-1),metrics(capHeight=0),metrics(capHeight=1e8)]:
            with self.assertRaises(CompanionError): resolve('Cap height',letter('A'),m)
        with self.assertRaises(CompanionError): resolve('Descender',letter('p'),metrics(descender=550))

    def test_manual_override_policy(self):
        self.assertEqual(mode_after_edit('Auto','height'),'Custom')
        self.assertEqual(mode_after_edit('Descender','bottom'),'Custom')
        self.assertEqual(mode_after_edit('Auto','horizontal'),'Auto')

    def test_native_metric_store_mapping(self):
        host=GlyphsHost.__new__(GlyphsHost); host.assert_main=lambda:None
        types={1:'baseline',2:'capHeight',3:'xHeight',4:'ascender',5:'descender'}
        general=NS(id='cap',type=2,filter=None)
        specific=NS(id='filtered',type=2,filter='case=upper')
        master=NS(capHeight=700,xHeight=500,ascender=800,descender=-200,
                  metrics={'cap':NS(position=701)})
        owner=NS(master=master,parent=NS(parent=NS(metrics=[general])),
                 metrics=[NS(metric=general,position=701,filter=None),
                          NS(metric=specific,position=675.5,filter='case=upper')])
        resolved=host.read_metrics(owner,types)
        self.assertEqual(resolved.get('capHeight'),675.5)
        self.assertEqual(resolved.get('baseline'),0)
        owner.metrics=[]
        self.assertEqual(host.read_metrics(owner,types).get('capHeight'),701)

    def test_changed_metrics_block_apply_before_mutation(self):
        host=FakeHost(); state=[metrics()]
        host.metrics=lambda owner:state[0]
        host.classification=lambda glyph:letter('A')
        target=capture(host,'foreground')
        state[0]=metrics(capHeight=720)
        with self.assertRaisesRegex(CompanionError,'metrics changed'): apply_paths(host,target,sample()['paths'])
        self.assertEqual(host.events,[])

    def test_changed_classification_blocks_apply(self):
        host=FakeHost(); host.metrics=lambda owner:metrics()
        host.classification=lambda glyph:letter('A')
        target=capture(host,'foreground')
        host.classification=lambda glyph:letter('a')
        with self.assertRaisesRegex(CompanionError,'classification changed'): revalidate(host,target)


class PreviewTests(unittest.TestCase):
    def test_shared_coordinates_and_closing_cubic(self):
        data=sample()
        data['paths']=[contour([(0,0),(100,0),(100,100),(0,100)],['curve','line','offcurve','offcurve'])]
        data['bounds']=[0,0,100,75]
        fit=resolve('Custom',letter('A'),metrics(),150,-50)
        preview=geometry(data,fit,25,metrics())
        self.assertEqual(preview.paths,place(data,150,-50,25))
        self.assertEqual(preview.commands,(('M',(25.0,-50.0)),('L',(225.0,-50.0)),
            ('C',(225.0,150.0,25.0,150.0,25.0,-50.0)),('Z',())))
        self.assertEqual(preview.ink_bounds,(25,-50,225,100))
        self.assertEqual(preview.image_bounds,(25,-50,2201,2126))

    def test_counter_winding_and_guides(self):
        data=sample(); data['paths'].append(contour([(30,40),(90,40),(90,100),(30,100)]))
        result=geometry(data,resolve('Cap height',letter('O'),metrics()),0,metrics())
        self.assertLess(signed_area(result.paths[0])*signed_area(result.paths[1]),0)
        self.assertEqual(dict(result.guides)['descender'],-200)

    def test_placement_does_not_retrace_or_mutate_result(self):
        data=sample(); original=sample()
        for height in [300,700,900]:
            preview=geometry(data,resolve('Custom',letter('A'),metrics(),height,0),10,metrics())
            self.assertAlmostEqual(preview.ink_bounds[3],height)
        self.assertEqual(data,original)

    def test_overlay_lifecycle_target_binding_and_no_duplicate_callbacks(self):
        events=[]; owner,destination,other=object(),object(),object()
        callback=lambda layer,info:None
        overlay=OverlayBinding(lambda fn,hook:events.append(('add',fn,hook)),
            lambda fn:events.append(('remove',fn)),lambda:events.append(('redraw',)),callback,'foreground',lambda a,b:a is b)
        payload=object()
        overlay.publish(owner,destination,payload)
        overlay.publish(owner,destination,payload)
        self.assertEqual(len([e for e in events if e[0]=='add']),1)
        self.assertTrue(overlay.matches(owner)); self.assertTrue(overlay.matches(destination))
        self.assertFalse(overlay.matches(other))
        overlay.clear()
        self.assertFalse(overlay.matches(owner)); self.assertIsNone(overlay.payload)
        overlay.publish(owner,destination,payload)
        overlay.close(); overlay.close(); overlay.publish(owner,destination,payload)
        self.assertFalse(overlay.matches(owner))
        self.assertEqual(len([e for e in events if e[0]=='remove']),2)

    def test_overlay_toggle_off_removes_callback(self):
        added=[]; removed=[]
        overlay=OverlayBinding(lambda *a:added.append(a),lambda a:removed.append(a),lambda:None,object(),'hook',lambda a,b:a is b)
        owner=object(); overlay.publish(owner,owner,object(),False)
        self.assertFalse(added)
        overlay.publish(owner,owner,object(),True); overlay.publish(owner,owner,object(),False)
        self.assertEqual(len(added),1); self.assertEqual(len(removed),1)


class InspectorStateTests(unittest.TestCase):
    def test_action_states(self):
        s=Session(); self.assertFalse(actions(s,True,True).trace_enabled)
        s.target=object()
        self.assertEqual(actions(s,True,False).primary,'trace')
        token,_=s.begin(s.target)
        state=actions(s,True,False)
        self.assertTrue(state.cancel_visible); self.assertFalse(state.trace_enabled)
        s.complete(token,sample())
        self.assertFalse(actions(s,True,False).apply_enabled) # unresolved Auto
        state=actions(s,True,True)
        self.assertEqual((state.primary,state.trace_title),('apply','Retrace'))
        s.mark_applied(); self.assertFalse(actions(s,True,True).apply_enabled)
        s.close(); self.assertFalse(actions(s,True,True).trace_enabled)

    def test_settings_and_cancel_clear_stale_results(self):
        s=Session(); token,event=s.begin(object()); s.complete(token,sample())
        s.invalidate()
        self.assertFalse(actions(s,True,True).apply_enabled)
        self.assertTrue(event.is_set()); self.assertFalse(s.complete(token,sample()))

    def test_image_drop_extensions(self):
        for name in ['glyph.png','glyph.JPG','two words.jpeg']:
            self.assertTrue(accepts_image(Path(name)))
        for name in ['glyph.svg','folder','glyph.png.txt']:
            self.assertFalse(accepts_image(Path(name)))


if __name__=='__main__': unittest.main()
