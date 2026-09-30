# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import os
import json
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time
import unittest
from test_contract import ROOT, sample
from beztrace_companion.contract import CompanionError,MAX_INPUT
from beztrace_companion.engine import trace,run_process,arguments,Cancelled,DEFAULT_ENGINE,default_engine
from beztrace_companion.session import Session


class ProcessTests(unittest.TestCase):
    def test_source_checkout_prefers_executable_development_engine(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); (root/'Package.swift').write_text('')
            (root/'Companions/Glyphs').mkdir(parents=True)
            module=root/'Companions/Glyphs/plugin/beztrace_companion/engine.py'
            module.parent.mkdir(parents=True); module.write_text('')
            development=root/'.build/beztrace-0.1.1-dev.4/bin/beztrace'
            development.parent.mkdir(parents=True); development.write_text('#!/bin/sh\n')
            development.chmod(0o755)
            self.assertEqual(default_engine(module),str(development.resolve()))

    def test_packaged_or_missing_development_engine_uses_release(self):
        with tempfile.TemporaryDirectory() as directory:
            packaged=Path(directory)/'Beztrace.glyphsPlugin/Contents/Resources/beztrace_companion/engine.py'
            packaged.parent.mkdir(parents=True); packaged.write_text('')
            self.assertEqual(default_engine(packaged),DEFAULT_ENGINE)
            root=Path(directory)/'checkout'; (root/'Package.swift').parent.mkdir(parents=True,exist_ok=True)
            (root/'Package.swift').write_text(''); (root/'Companions/Glyphs').mkdir(parents=True)
            module=root/'Companions/Glyphs/plugin/engine.py'; module.parent.mkdir(parents=True); module.write_text('')
            self.assertEqual(default_engine(module),DEFAULT_ENGINE)

    def run_python(self,source,timeout=2,limit=4096,cancel=None,input=b''):
        return run_process(sys.executable,['-c',source],input,cancel or threading.Event(),timeout,limit)

    def test_diagnostics_option_is_exposed_and_validated(self):
        args=arguments({'diagnostics':'summary'})
        self.assertEqual(args[args.index('--diagnostics')+1],'summary')
        with self.assertRaises(CompanionError): arguments({'diagnostics':'verbose'})

    def test_concurrent_pipe_drain(self):
        code,out,err=self.run_python('import sys; sys.stderr.write("e"*60000); data=sys.stdin.buffer.read(); sys.stdout.buffer.write(data)',input=b'x'*200000,limit=300000)
        self.assertEqual((code,len(out),len(err)),(0,200000,60000))

    def test_timeout_and_cancel(self):
        start=time.monotonic()
        with self.assertRaisesRegex(CompanionError,'timed out'):
            self.run_python('import time; time.sleep(10)',timeout=.1)
        self.assertLess(time.monotonic()-start,2)
        cancel=threading.Event(); timer=threading.Timer(.1,cancel.set); timer.start()
        with self.assertRaises(Cancelled): self.run_python('import time; time.sleep(10)',cancel=cancel)
        timer.join()

    def test_termination_escalates_and_reaps(self):
        start=time.monotonic()
        with self.assertRaises(CompanionError):
            self.run_python('import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(10)',timeout=.15)
        self.assertLess(time.monotonic()-start,2)

    def test_output_limits(self):
        for source in ['import sys; sys.stdout.write("x"*100000)','import sys; sys.stderr.write("x"*100000)']:
            with self.assertRaisesRegex(CompanionError,'buffer limit'): self.run_python(source)

    def test_missing_executable(self):
        with self.assertRaisesRegex(CompanionError,'executable'): run_process('/no/beztrace',[],b'',threading.Event(),1)

    def fake(self,version='beztrace 0.1.0',status=0,output='{}'):
        tmp=tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        path=Path(tmp.name)/'engine with spaces'
        path.write_text('#!'+sys.executable+'\nimport sys\nif "--version" in sys.argv:\n print('+repr(version)+')\nelse:\n print('+repr(output)+')\n sys.exit('+str(status)+')\n')
        path.chmod(0o755)
        return str(path)

    def test_incompatible_version(self):
        with self.assertRaisesRegex(CompanionError,'Incompatible'): trace(self.fake(version='beztrace 0.2.0'),b'image',{})

    def test_supported_versions_must_match_json(self):
        versions = ('0.1.0', '0.1.1-dev.1', '0.1.1-dev.2', '0.1.1-dev.3', '0.1.1-dev.4')
        for executable_version in versions:
            for json_version in versions:
                result = sample(); result['engine']['version'] = json_version
                engine = self.fake(version='beztrace ' + executable_version, output=json.dumps(result))
                if executable_version == json_version:
                    self.assertEqual(trace(engine, b'image', {})['engine']['version'], json_version)
                else:
                    with self.assertRaisesRegex(CompanionError, 'does not match'):
                        trace(engine, b'image', {})

    def test_all_exit_codes(self):
        for status in [2,3,4,5,6,7,99]:
            with self.subTest(status=status):
                with self.assertRaises(CompanionError): trace(self.fake(status=status),b'image',{})

    def test_invalid_success_output(self):
        for output in ['{}','not JSON','[]']:
            with self.assertRaises(CompanionError): trace(self.fake(output=output),b'image',{})

    def test_empty_and_oversize(self):
        for data in [b'',b'x'*(MAX_INPUT+1)]:
            with self.assertRaises(CompanionError): trace('/missing',data,{})

    def test_options(self):
        self.assertIn('--no-refine-raster',arguments(dict(refine_raster=False)))
        for options in [dict(grid=2.5),dict(threshold=256),dict(accuracy=0),dict(smoothing=float('nan')),dict(invert=1),dict(corner_threshold=180),dict(unknown=1)]:
            with self.assertRaises(CompanionError): arguments(options)
        self.assertNotIn('--target-y-min',arguments({}))

    def test_stale_completion_and_repeated_apply(self):
        s=Session(); token,cancel=s.begin(object()); s.invalidate()
        self.assertTrue(cancel.is_set()); self.assertFalse(s.complete(token,{'paths':[]}))
        token,_=s.begin(object()); self.assertTrue(s.complete(token,{'paths':[1]}))
        self.assertTrue(s.can_apply()); s.mark_applied(); self.assertFalse(s.can_apply())
        with self.assertRaises(CompanionError): s.mark_applied()
        token,_=s.begin(object()); s.close(); self.assertFalse(s.complete(token,{'paths':[1]}))

    def test_poisoned_session(self):
        s=Session(); s.poisoned=True
        with self.assertRaises(CompanionError): s.begin(object())


class ReleasedEngineTests(unittest.TestCase):
    def test_released_engine_corpus(self):
        executable=os.environ.get('BEZTRACE_TEST_ENGINE',DEFAULT_ENGINE)
        self.assertTrue(Path(executable).is_file(),'Released engine required: set BEZTRACE_TEST_ENGINE')
        fixtures=ROOT.parents[1]/'Tests/Fixtures/corpus'
        images=sorted(fixtures.rglob('*.png'))
        images=[p for p in images if 'traced-review' not in p.parts]
        self.assertEqual(len(images),100)
        for path in images:
            with self.subTest(image=path.name):
                result=trace(executable,path.read_bytes(),{})
                self.assertTrue(result['paths'])


if __name__=='__main__': unittest.main()
