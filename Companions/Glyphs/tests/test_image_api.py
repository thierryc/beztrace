# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch
from test_contract import sample
from test_adapter import FakeHost,Layer
from beztrace_companion.api import ImportRequest,prepare_imports,apply_imports
from beztrace_companion.adapter import Target,apply_image,RecoveryError
from beztrace_companion.canvas import ImageGeometry
from beztrace_companion.placement import GlyphClass,MetricSnapshot
from beztrace_companion.contract import CompanionError
from beztrace_companion.engine import Cancelled
from beztrace_companion import image_io


class Host(FakeHost):
    def __init__(self):
        super().__init__(); self.layers={name:Layer() for name in ('A','B','fl')}
        for layer in self.layers.values(): layer.backgroundImage=None
        self.undo=0; self.assignment=0; self.bad_assignment=None; self.bad_recovery=False
    def target(self,font,glyph,layer_id,destination,sizing=False):
        if font is not self.font or glyph not in self.layers or layer_id!='master': raise CompanionError('Missing target')
        layer=self.layers[glyph]
        if destination not in ('foreground','background'): raise CompanionError('destination')
        return Target(self.document,font,glyph,layer,layer,destination,(glyph,layer_id),self.fingerprint(layer),glyph,
            MetricSnapshot((('baseline',0),('capHeight',700),('xHeight',500))),GlyphClass(glyph,glyph.encode().hex().upper(),'upper','Letter'))
    def contains(self,t): return self.present and self.layers.get(t.glyph) is t.layer
    def metrics(self,owner): return MetricSnapshot((('baseline',0),('capHeight',700),('xHeight',500)))
    def classification(self,glyph): return GlyphClass(glyph,glyph.encode().hex().upper(),'upper','Letter')
    def new_image(self,path): return NS(path=path,transform=(1,0,0,1,0,0))
    def image_state(self,image): return (image.path,tuple(image.transform)) if image else None
    def fingerprint(self,layer): return (super().fingerprint(layer),self.image_state(layer.backgroundImage))
    def content_without_image(self,layer): return super().fingerprint(layer)
    def set_image(self,layer,image):
        self.assignment+=1; layer.backgroundImage=image
        if self.assignment==self.bad_assignment or (image is None and self.bad_recovery): raise RuntimeError('Injected image fault')


class ImageAPITests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'image.png'; self.path.write_bytes(b'image')
        self.host=Host()
        def snap(img):
            return image_io.ImageSnapshot(img.path,None,ImageGeometry((100,100),(0,0,100,100),(1,0,0,1,0,0)),img,image_io.file_state(img.path))
        self.addCleanup(patch.stopall)
        patch('beztrace_companion.api.image_io.snapshot',side_effect=snap).start()
        patch('beztrace_companion.api.image_io.prepare',return_value=(b'image',image_io.digest(b'image'))).start()
        patch('beztrace_companion.api.trace',return_value=sample()).start()
    def request(self,name='A',**kwargs): return ImportRequest(str(self.path),name,'master',**kwargs)
    def prepare(self,entries):
        job=prepare_imports(self.host.font,entries,_host=self.host)
        self.assertTrue(job._done.wait(2))
        return job
    def test_prepare_is_read_only_and_fit_applies_image_only(self):
        before=[self.host.fingerprint(l) for l in self.host.layers.values()]
        job=self.prepare([self.request()])
        self.assertEqual(before,[self.host.fingerprint(l) for l in self.host.layers.values()])
        result=apply_imports(job.plan,_host=self.host)
        self.assertEqual(result['completed'],1); self.assertEqual(self.host.undo,0)
        layer=self.host.layers['A']; self.assertEqual(layer.width,0)
        self.assertEqual(layer.shapes,['existing path','component'])
        self.assertIsNotNone(layer.backgroundImage)
        with self.assertRaises(CompanionError): apply_imports(job.plan,_host=self.host)
    def test_auto_ambiguous_and_missing_targets_fail_before_worker(self):
        for request in [self.request('fl'),self.request('missing')]:
            with self.assertRaises(CompanionError): self.prepare([request])
        self.assertEqual(self.host.assignment,0)
    def test_duplicate_and_conflict_preflight(self):
        with self.assertRaises(CompanionError): self.prepare([self.request(),self.request()])
        self.host.layers['A'].backgroundImage=self.host.new_image(str(self.path))
        with self.assertRaises(CompanionError): self.prepare([self.request()])
        self.assertEqual(apply_imports(self.prepare([self.request(replace=True)]).plan,_host=self.host)['completed'],1)
    def test_changed_source_or_layer_prevents_entire_batch(self):
        for source in (True,False):
            job=self.prepare([self.request(),self.request('B')])
            if source: self.path.write_bytes(b'changed')
            else: self.host.layers['B'].width=900
            with self.assertRaises(CompanionError): apply_imports(job.plan,_host=self.host)
            self.assertEqual(self.host.assignment,0)
            self.path.write_bytes(b'image')
    def test_cancel_prepared_job_prevents_mutation(self):
        job=self.prepare([self.request()]); plan=job.plan; job.cancel()
        with self.assertRaises(Cancelled): apply_imports(plan,_host=self.host)
        self.assertEqual(self.host.assignment,0)
    def test_partial_failure_restores_failing_item_and_stops(self):
        job=self.prepare([self.request(),self.request('B'),self.request('fl',preset='Custom')])
        self.host.bad_assignment=2
        result=apply_imports(job.plan,_host=self.host)
        self.assertEqual([r['status'] for r in result['items']],['applied','failed','not-applied'])
        self.assertIsNone(self.host.layers['B'].backgroundImage)
        self.assertEqual(self.host.undo,0)
    def test_recovery_failure_reported(self):
        job=self.prepare([self.request()]); self.host.bad_assignment=1; self.host.bad_recovery=True
        result=apply_imports(job.plan,_host=self.host)
        self.assertEqual(result['items'][0]['status'],'recovery-failed'); self.assertEqual(self.host.undo,0)
    def test_prepared_image_tamper_rejected(self):
        job=self.prepare([self.request()]); job.plan.items[0].image.transform=(2,0,0,2,0,0)
        with self.assertRaises(CompanionError): apply_imports(job.plan,_host=self.host)
        self.assertEqual(self.host.assignment,0)

    def test_worker_failure_has_no_plan_and_no_writes(self):
        with patch('beztrace_companion.api.trace',side_effect=CompanionError('empty image')):
            job=self.prepare([self.request()])
        with self.assertRaisesRegex(CompanionError,'empty image'): _=job.plan
        self.assertEqual(self.host.assignment,0)

    def test_cancel_during_worker_never_produces_applicable_plan(self):
        entered=threading.Event(); release=threading.Event()
        def slow(*args): entered.set(); release.wait(2); return sample()
        with patch('beztrace_companion.api.trace',side_effect=slow):
            job=prepare_imports(self.host.font,[self.request()],_host=self.host)
            self.assertTrue(entered.wait(2)); job.cancel(); release.set()
            self.assertTrue(job._done.wait(2))
        with self.assertRaises(Cancelled): _=job.plan
        self.assertEqual(self.host.assignment,0)

    def test_native_image_revalidation_checks_identity_geometry_and_bytes(self):
        image=self.host.new_image(str(self.path)); self.host.layers['A'].backgroundImage=image
        target=self.host.target(self.host.font,'A','master','foreground')
        snap=image_io.snapshot(image)
        self.host.same=lambda a,b:a is b
        with patch('beztrace_companion.image_io.native_geometry',return_value=snap.geometry):
            image_io.revalidate(self.host,target,snap,image_io.digest(b'image'))
            with self.assertRaises(CompanionError): image_io.revalidate(self.host,target,snap,'bad-hash')
            target.layer.backgroundImage=self.host.new_image(str(self.path))
            with self.assertRaises(CompanionError): image_io.revalidate(self.host,target,snap,image_io.digest(b'image'))
            target.layer.backgroundImage=image
        with patch('beztrace_companion.image_io.native_geometry',return_value=ImageGeometry((100,100),(0,0,100,100),(2,0,0,2,0,0))):
            with self.assertRaises(CompanionError): image_io.revalidate(self.host,target,snap,image_io.digest(b'image'))
