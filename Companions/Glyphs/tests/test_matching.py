# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from test_contract import ROOT
from beztrace_companion.contract import CompanionError
from beztrace_companion.adapter import RecoveryError
from beztrace_companion import matching,matching_contract,hoi,hoi_geometry
from beztrace_companion.matching_preview import payload

REPO=ROOT.parents[1]
ENGINE=Path(os.environ.get('BEZTRACE_MATCH_ENGINE',str(REPO/'.build/release/beztrace')))
FIXTURES=REPO/'Tests/Fixtures/matching/v1'


def result(name='shifted-start'):
    if not ENGINE.is_file(): raise AssertionError('Build the matching engine before running companion matching tests')
    return matching_contract.parse_master_set(subprocess.check_output([str(ENGINE),'match',str(FIXTURES/(name+'.json'))]))


class Layer:
    def __init__(self,paths):
        self.shapes=copy.deepcopy(paths); self.width=0; self.anchors=[('top',50,100)]
        self.rounding=False


class Host:
    def __init__(self,packet):
        self.layers=[Layer(m['outline']['contours']) for m in packet['sourceMasters']]
        self.glyph=object(); self.font=object(); self.present=True; self.axis=('wght',100,900)
        self.events=[]; self.fail=None; self.recovery_fail=False; self.native_available=False
    def assert_main(self): pass
    def fingerprint(self,layer): return copy.deepcopy((layer.shapes,layer.width,layer.anchors))
    def context(self,font,glyph,reference_id):
        return dict(font=self.font,glyph=self.glyph,targets=[SimpleNamespace(layer=l,owner=SimpleNamespace(layerId=str(i))) for i,l in enumerate(self.layers)],
                    outlines=[dict(contours=copy.deepcopy(l.shapes)) for l in self.layers],axis=dict(tag='wght',locations=[100,900]),
                    unitsPerEm=1000,axis_fingerprint=self.axis,fingerprints=[self.fingerprint(l) for l in self.layers])
    def revalidate_match(self,ctx):
        if not self.present or self.axis!=ctx['axis_fingerprint'] or [self.fingerprint(l) for l in self.layers]!=ctx['fingerprints']:
            raise CompanionError('stale target')
    def stage(self,ctx,packet): return dict(layers=[Layer(packet[r]['outline']['contours']) for r in ('reference','target')],context=ctx)
    def hoi_available(self): return self.native_available
    def snapshot(self,layer): return self.fingerprint(layer)
    def rounding_state(self,layer): return layer.rounding
    def set_rounding(self,layer,value): layer.rounding=value
    def begin_undo(self,glyph): self.events.append('begin')
    def end_undo(self,glyph): self.events.append('end')
    def install_stage(self,ctx,stage):
        for i,(target,source) in enumerate(zip(ctx['targets'],stage['layers'])):
            target.layer.shapes=copy.deepcopy(source.shapes)
            if self.fail=='install' and i==1: raise RuntimeError('second master fault')
    def verify_stage(self,ctx,stage,snapshots):
        if self.fail=='verify': raise RuntimeError('verification fault')
        for target,source,before in zip(ctx['targets'],stage['layers'],snapshots):
            assert target.layer.shapes==source.shapes
            assert (target.layer.width,target.layer.anchors)==before[1:]
    def restore(self,layer,snapshot):
        if self.recovery_fail: raise RuntimeError('recovery fault')
        layer.shapes,layer.width,layer.anchors=copy.deepcopy(snapshot)
    def redraw(self): self.events.append('redraw')


def finish(job):
    limit=time.monotonic()+5
    while not job.done and time.monotonic()<limit:
        job.advance(); time.sleep(.005)
    if not job.done: raise AssertionError('Preparation timeout')
    return job.plan


class MatchingContractTests(unittest.TestCase):
    def test_budget_defaults_validation_and_old_engine_rejection(self):
        self.assertEqual(matching.options(None)['maxAdditionalOnCurveNodes'],0)
        for value in ({'maxAdditionalOnCurveNodes':-1},{'maxAdditionalOnCurveNodes':True},{'maxOnCurveNodes':2},{'maxNodes':1},{'maxNodes':4097}):
            with self.assertRaises(CompanionError): matching.options(value)
        with patch.object(matching_contract,'capabilities',return_value={'matchSchemaVersion':1}):
            with self.assertRaisesRegex(CompanionError,'point-budget support'):
                matching_contract.match(str(ENGINE),{'options':{'maxNodes':64}},threading.Event())
    def test_import_and_apply_recheck_actual_budget(self):
        fixture=REPO/'Tests/Fixtures/matching/budget-v1/shared-explicit-budget.json'
        packet=matching_contract.parse_master_set(subprocess.check_output([str(ENGINE),'match',str(fixture)]))
        host=Host(packet); before=[host.fingerprint(l) for l in host.layers]
        data=matching_contract.export_bytes(packet)
        with self.assertRaisesRegex(CompanionError,'point budget'):
            matching.prepare_match(host.font,'A','0',settings=dict(repairHOI=False),engine=str(ENGINE),imported=data,confirm_axis=True,_host=host)
        plan=finish(matching.prepare_match(host.font,'A','0',settings=dict(repairHOI=False,maxAdditionalOnCurveNodes=2),engine=str(ENGINE),imported=data,confirm_axis=True,_host=host))
        plan.settings['maxAdditionalOnCurveNodes']=0
        with self.assertRaisesRegex(CompanionError,'point budget'): matching.apply_match(plan)
        self.assertEqual(before,[host.fingerprint(l) for l in host.layers]); self.assertFalse(plan.consumed)
    def test_real_engine_capabilities_and_exchange(self):
        self.assertEqual(matching_contract.capabilities(str(ENGINE))['matchSchemaVersion'],1)
        value=result()
        self.assertEqual(matching_contract.parse_master_set(matching_contract.export_bytes(value)),value)
        self.assertEqual(matching_contract.export_bytes(value),matching_contract.export_bytes(copy.deepcopy(value)))
        self.assertFalse(value['interpolation']['nativeHOIVerified'])
    def test_rejects_bad_structure_versions_and_hoi(self):
        original=result()
        mutations=[lambda v:v.update(schemaVersion=9),lambda v:v['target']['outline']['contours'][0]['nodes'].pop(),
                   lambda v:v['reference']['outline']['contours'][0]['nodes'][0].update(x=float('nan')),
                   lambda v:v['contours'][0].update(targetSourceNodes=[999]*4),
                   lambda v:v.update(extensions={'glyphs4':dict(schemaVersion=1,axisTag='wght',entries=[dict(master=1,contour=0,node=0,ip=[1,2])])}),
                   lambda v:v.update(extensions={'glyphs4':dict(schemaVersion=1,axisTag='wght',entries=[dict(master=0,contour=0,node=0,ip=[float('inf'),2])])})]
        for mutation in mutations:
            value=copy.deepcopy(original); mutation(value)
            with self.assertRaises(CompanionError): matching_contract.parse_master_set(json.dumps(value).encode())
        for data in (b'{}',b'{"schemaVersion":1,"schemaVersion":1}',b'[]'):
            with self.assertRaises(CompanionError): matching_contract.parse_master_set(data)
    def test_preview_is_pure_and_does_not_change_packet(self):
        value=result(); before=copy.deepcopy(value)
        host=Host(value); ctx=host.context(None,'A','0')
        view=payload(ctx,value,factor=.5)
        self.assertTrue(view['links']); self.assertEqual(value,before)


class MatchingTransactionTests(unittest.TestCase):
    def setUp(self): self.packet=result(); self.host=Host(self.packet)
    def prepare(self,settings=None,**kwargs):
        return matching.prepare_match(self.host.font,'A','0',settings=settings or dict(repairHOI=False),engine=str(ENGINE),_host=self.host,**kwargs)
    def test_prepare_is_readonly_then_one_two_layer_apply(self):
        before=[self.host.fingerprint(l) for l in self.host.layers]
        plan=finish(self.prepare())
        self.assertEqual([self.host.fingerprint(l) for l in self.host.layers],before)
        self.assertEqual(matching.apply_match(plan)['status'],'applied')
        self.assertEqual(self.host.events,['begin','end','redraw'])
        self.assertEqual(self.host.layers[0].width,0)
        self.assertEqual(self.host.layers[1].anchors,before[1][2])
        with self.assertRaises(CompanionError): matching.apply_match(plan)
    def test_stale_outline_axis_and_closed_document_fail_before_write(self):
        for change in (lambda h:h.layers[1].shapes[0]['nodes'][0].update(x=999),lambda h:setattr(h,'axis',('wght',0,1)),lambda h:setattr(h,'present',False)):
            self.host=Host(self.packet); plan=finish(self.prepare()); change(self.host)
            with self.assertRaises(CompanionError): matching.apply_match(plan)
            self.assertEqual(self.host.events,[])
    def test_second_layer_failure_rolls_back_both_and_rounding(self):
        for phase in ('install','verify'):
            self.host=Host(self.packet); self.host.layers[0].rounding=True
            plan=finish(self.prepare()); before=[self.host.fingerprint(l) for l in self.host.layers]
            self.host.fail=phase
            with self.assertRaisesRegex(CompanionError,'both master layers were restored'): matching.apply_match(plan)
            self.assertEqual([self.host.fingerprint(l) for l in self.host.layers],before)
            self.assertEqual([l.rounding for l in self.host.layers],[True,False])
            self.assertEqual(self.host.events,['begin','end'])
    def test_recovery_failure_poisoning_and_consumption(self):
        plan=finish(self.prepare()); self.host.fail='install'; self.host.recovery_fail=True
        with self.assertRaises(RecoveryError): matching.apply_match(plan)
        self.assertTrue(plan.poisoned); self.assertTrue(plan.consumed)
        with self.assertRaises(CompanionError): matching.apply_match(plan)
    def test_cancel_before_or_after_preparation(self):
        for ready in (False,True):
            self.host=Host(self.packet); job=self.prepare()
            if ready: plan=finish(job)
            job.cancel(); job.advance()
            with self.assertRaises(CompanionError): _=job.plan
            if ready:
                with self.assertRaises(CompanionError): matching.apply_match(plan)
            self.assertEqual(self.host.events,[])
    def test_import_requires_mapping_and_upm_and_rechecks_claims(self):
        data=matching_contract.export_bytes(self.packet)
        with self.assertRaisesRegex(CompanionError,'confirm'): self.prepare(imported=data)
        bad=copy.deepcopy(self.packet); bad['unitsPerEm']=2048
        with self.assertRaisesRegex(CompanionError,'UPM'): self.prepare(imported=matching_contract.export_bytes(bad),confirm_axis=True)
        plan=finish(self.prepare(imported=data,confirm_axis=True))
        self.assertNotIn('extensions',plan.result)
        self.assertEqual(matching_contract.parse_master_set(matching.export_match(plan)),plan.result)
    def test_unavailable_hoi_requires_explicit_matching_only(self):
        job=self.prepare(dict(repairHOI=True))
        with self.assertRaisesRegex(CompanionError,'unavailable'): finish(job)
        self.assertEqual(self.host.events,[])


class FakeEvaluator:
    def clone(self,stage): return copy.deepcopy(stage)
    def endpoints(self,stage): return copy.deepcopy(stage['paths'])
    def set_ip(self,stage,entry): stage['entries'][(entry['contour'],entry['node'])]=copy.deepcopy(entry)
    def has_local(self,stage,ci,indices): return any((ci,i) in stage['entries'] for i in indices)
    def sample(self,stage,t):
        a,b=stage['paths']; result=[]
        for ci,(p,q) in enumerate(zip(a,b)):
            nodes=[]
            for ni,(x,y) in enumerate(zip(p['nodes'],q['nodes'])):
                node=dict(x,x=x['x']+(y['x']-x['x'])*t,y=x['y']+(y['y']-x['y'])*t)
                entry=stage['entries'].get((ci,ni))
                if entry:
                    for k,axis in enumerate(('x','y')): node[axis]+=4*t*(1-t)*(entry['ip'][k]-(x[axis]+y[axis])/2)
                nodes.append(node)
            result.append(dict(closed=True,nodes=nodes))
        return result


def synthetic_stage(scale=.05):
    def path(points):
        return dict(closed=True,nodes=[dict(x=x*scale,y=y*scale,type=kind,smooth=i==3)
            for i,(x,y,kind) in enumerate(points)])
    a=path([(80,40,'line'),(30,110,'offcurve'),(60,200,'offcurve'),(200,200,'curve'),(240,200,'offcurve'),(330,130,'offcurve'),(320,50,'curve')])
    b=path([(80,40,'line'),(300,60,'offcurve'),(300,120,'offcurve'),(300,200,'curve'),(300,400,'offcurve'),(440,390,'offcurve'),(440,50,'curve')])
    return dict(paths=[[a],[b]],entries={},context=dict(unitsPerEm=1000,axis=dict(tag='wght',locations=[100,900])))


def drain(generator):
    while True:
        try: next(generator)
        except StopIteration as final: return final.value


class HOIPreparationTests(unittest.TestCase):
    def test_preserved_endpoint_residual_above_detection_is_not_an_impossible_repair(self):
        stage=synthetic_stage()
        stage['paths'][0][0]['nodes'][2]['y']=2.
        stage['paths'][1]=copy.deepcopy(stage['paths'][0])
        before=copy.deepcopy(stage)
        with patch.object(hoi_geometry,'candidates',side_effect=AssertionError('No intermediate excess to repair')):
            report=drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),evaluator=FakeEvaluator()))
        self.assertTrue(report['nativeVerified'],report['unresolved'])
        self.assertGreater(report['joinChecks'][0]['before'],1)
        self.assertLessEqual(report['joinChecks'][0]['finalPeak'],report['joinChecks'][0]['limit'])
        self.assertEqual(report['entries'],[]); self.assertEqual(stage,before)
    def test_repairs_verify_against_endpoint_limit_when_endpoints_exceed_detection(self):
        stage=synthetic_stage(); stage['paths'][0][0]['nodes'][2]['y']=2.
        stage['paths'][1][0]['nodes'][2]['y']=9.
        stage['paths'][1][0]['nodes'][4]['y']=30.
        before=copy.deepcopy(stage)
        report=drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),evaluator=FakeEvaluator()))
        self.assertTrue(report['nativeVerified'],report['unresolved']); self.assertTrue(report['entries'])
        check=report['joinChecks'][0]
        self.assertGreater(check['before'],check['limit'])
        self.assertGreater(check['finalPeak'],1)
        self.assertLessEqual(check['finalPeak'],check['limit'])
        self.assertEqual(stage,before)
    def test_detached_repair_and_interleaved_sampling(self):
        stage=synthetic_stage(); before=copy.deepcopy(stage)
        report=drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),evaluator=FakeEvaluator()))
        self.assertTrue(report['nativeVerified'],report['unresolved']); self.assertEqual(report['sampleCount'],201)
        self.assertTrue(report['entries']); self.assertEqual(stage,before)
        self.assertLessEqual(report['maximumDeviation'],5)
    def test_shape_limit_and_existing_local_hoi_block_repairs(self):
        stage=synthetic_stage(1.)
        report=drain(hoi.prepare(stage,None,dict(matching.DEFAULT_SETTINGS,maxShapeMovement=.00001),threading.Event(),evaluator=FakeEvaluator()))
        self.assertFalse(report['nativeVerified']); self.assertTrue(report['unresolved'])
        stage=synthetic_stage(); stage['entries'][(0,3)]=dict(master=0,contour=0,node=3,ip=[12.5,10])
        report=drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),evaluator=FakeEvaluator()))
        self.assertTrue(report['unresolved'])
    def test_cancellation_and_clean_noop(self):
        stage=synthetic_stage(); event=threading.Event(); event.set()
        with self.assertRaises(CompanionError): drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,event,evaluator=FakeEvaluator()))
        stage['paths'][1]=copy.deepcopy(stage['paths'][0])
        report=drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),evaluator=FakeEvaluator()))
        self.assertTrue(report['nativeVerified']); self.assertEqual(report['entries'],[])
    def test_imported_settings_are_rechecked_and_movement_is_bounded(self):
        stage=synthetic_stage()
        entries=[dict(master=0,contour=0,node=3,ip=[1000,1000])]
        with self.assertRaises(CompanionError): drain(hoi.prepare(stage,None,matching.DEFAULT_SETTINGS,threading.Event(),entries,evaluator=FakeEvaluator()))
