# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import unittest
from test_matching import ENGINE,REPO,Host,result,finish
from beztrace_companion import matching,matching_contract,matching_raster
from beztrace_companion.canvas import ImageGeometry
from beztrace_companion.contract import CompanionError

ROOT=REPO/'Tests/Fixtures/matching/raster-v1'


class RasterExchangeTests(unittest.TestCase):
    def setUp(self): self.host=Host(result())
    def snapshot(self,name='rectangle.png',geometry=None):
        return SimpleNamespace(path=str(ROOT/name),geometry=geometry or ImageGeometry((128.,128.),(0.,0.,128.,128.),(1.,0.,0.,1.,0.,0.)))
    def prepare(self,mode,name='wide-rectangle.png',smooth=False):
        snapshots=[(1,self.snapshot(name))] if mode==1 else [(0,self.snapshot()),(1,self.snapshot(name))]
        def bitmap(snapshot,cancel):
            data=Path(snapshot.path).read_bytes(); return data,hashlib.sha256(data).hexdigest()
        with patch.object(matching_raster,'capture',return_value=snapshots),patch.object(matching_raster.image_io,'prepare',side_effect=bitmap):
            return finish(matching.prepare_match(self.host.font,'A','0',settings=dict(repairHOI=False,referencePolicy='shared-subdivision',smoothJoins=smooth),
                source_mode=mode,engine=str(ENGINE),_host=self.host))
    def test_canvas_affine_includes_crop_and_full_raster_extent(self):
        geometry=ImageGeometry((400.,300.),(20.,30.,80.,60.),(1.5,.2,-.3,.9,100.,-5.))
        value=matching_raster.descriptor((ROOT/'rectangle.png').read_bytes(),self.snapshot(geometry=geometry),'a')
        m=value['transform']
        for actual,wanted in zip(m,[1.5*80/1088,.2*80/1088,-.3*60/1088,.9*60/1088,121.,26.]):
            self.assertAlmostEqual(actual,wanted,places=12)
        with self.assertRaises(CompanionError): matching_raster.descriptor(b'bad',self.snapshot(),'a')
    def test_trace_to_reference_uses_fixed_reference_and_explicit_budgets(self):
        before=[self.host.fingerprint(l) for l in self.host.layers]
        captured=[]; original=matching_contract.match
        def inspect(engine,request,cancel):
            captured.append(copy.deepcopy(request)); return original(engine,request,cancel)
        def bitmap(snapshot,cancel):
            data=Path(snapshot.path).read_bytes(); return data,hashlib.sha256(data).hexdigest()
        with patch.object(matching_raster,'capture',return_value=[(1,self.snapshot('wide-rectangle.png'))]), \
             patch.object(matching_raster.image_io,'prepare',side_effect=bitmap), \
             patch.object(matching_contract,'match',side_effect=inspect):
            plan=finish(matching.prepare_match(self.host.font,'A','0',source_mode=1,engine=str(ENGINE),_host=self.host,
                settings=dict(repairHOI=False,referencePolicy='fixed',maxAdditionalOnCurveNodes=0,maxOnCurveNodes=4,maxNodes=4)))
        self.assertEqual(captured[0]['mode'],'trace-to-reference')
        self.assertEqual(captured[0]['options']['referencePolicy'],'fixed')
        self.assertEqual(captured[0]['options']['maxAdditionalOnCurveNodes'],0)
        self.assertEqual(captured[0]['options']['maxOnCurveNodes'],4)
        self.assertEqual(captured[0]['options']['maxNodes'],4)
        self.assertNotIn('preserveStructure',captured[0]['options'])
        self.assertEqual(plan.result['reference']['outline'],plan.context['outlines'][0])
        self.assertEqual(before,[self.host.fingerprint(l) for l in self.host.layers])
    def test_both_raster_modes_are_detached_and_exchange_revalidates(self):
        for mode in (1,2):
            before=[self.host.fingerprint(l) for l in self.host.layers]
            plan=self.prepare(mode)
            self.assertEqual(before,[self.host.fingerprint(l) for l in self.host.layers])
            self.assertEqual(len(plan.result['rasterSources']),mode)
            self.assertTrue(plan.context['source_evidence'])
            data=matching.export_match(plan)
            imported=finish(matching.prepare_match(self.host.font,'A','0',settings=dict(repairHOI=False),
                engine=str(ENGINE),imported=data,confirm_axis=True,_host=self.host))
            for role in ('reference','target'): self.assertEqual(imported.result[role]['outline'],plan.result[role]['outline'])
            self.assertNotIn('extensions',imported.result)
    def test_structure_preserving_review_and_malformed_hoi(self):
        self.host.layers[1].shapes=copy.deepcopy(self.host.layers[0].shapes)
        plan=finish(matching.prepare_match(self.host.font,'A','0',settings=dict(repairHOI=False),source_mode=3,engine=str(ENGINE),_host=self.host))
        self.assertEqual(plan.result['reference']['outline'],plan.context['outlines'][0])
        self.assertEqual(plan.result['target']['outline'],plan.context['outlines'][1])
        for settings in ({'rc':'auto','rd':'cw'},{'rc':[0,1]},{'tl':1/3,'au':0},{'ip':[0,1]}):
            value=copy.deepcopy(plan.result)
            value['extensions']={'glyphs4':dict(schemaVersion=1,axisTag='wght',entries=[],preserved=[dict(master=0,contour=0,node=0,settings=settings)])}
            self.assertEqual(matching_contract.parse_master_set(json.dumps(value).encode()),value)
        for settings in ({'rc':'invalid'},{'ip':[1]},{'tl':'1/3'},{'unknown':1}):
            with self.assertRaises(CompanionError): matching_contract.validate_hoi_settings(settings)
    def test_smoothed_raster_import_keeps_original_certificate_and_201_position_review(self):
        plan=self.prepare(2,smooth=True)
        report=copy.deepcopy(plan.result['jointSmoothing'])
        self.assertGreater(report['proposalDeviation']['upperBound'],0)
        imported=finish(matching.prepare_match(self.host.font,'A','0',settings=dict(repairHOI=False),engine=str(ENGINE),
            imported=matching.export_match(plan),confirm_axis=True,_host=self.host))
        self.assertEqual(imported.result['jointSmoothing'],report)
        self.assertEqual(imported.result['interpolation']['sampleCount'],201)
        self.assertEqual(matching_contract.parse_master_set(matching.export_match(imported)),imported.result)
    def test_original_source_revalidation_is_part_of_native_guard(self):
        ctx={'targets':[object(),object()],'source_evidence':[(1,self.snapshot(),'hash')]}
        with patch.object(matching_raster.image_io,'revalidate',side_effect=CompanionError('image changed')) as check:
            with self.assertRaisesRegex(CompanionError,'image changed'): matching_raster.revalidate_sources(self.host,ctx)
            self.assertEqual(check.call_args.args[1],ctx['targets'][1])
