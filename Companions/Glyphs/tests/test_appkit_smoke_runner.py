# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import contextlib
import io
from pathlib import Path
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from appkit_smoke_runner import run_native


class AppKitSmokeRunnerTests(unittest.TestCase):
    def test_worker_uses_same_interpreter_and_preserves_arguments_and_failure(self):
        with patch('appkit_smoke_runner.subprocess.run',return_value=subprocess.CompletedProcess([],3)) as run:
            self.assertEqual(run_native('/tmp/smoke.py',['--output','/tmp/native evidence']),3)
        self.assertEqual(run.call_args.args[0],
                         [sys.executable,'-u','-X','faulthandler','/tmp/smoke.py','--native-worker',
                          '--output','/tmp/native evidence'])
        self.assertEqual(run.call_args.kwargs,dict(timeout=120,check=False))

    def test_abort_reports_native_failure_and_gui_requirement(self):
        output=io.StringIO()
        with patch('appkit_smoke_runner.subprocess.run',return_value=subprocess.CompletedProcess([],-signal.SIGABRT)),contextlib.redirect_stderr(output):
            self.assertEqual(run_native('/tmp/smoke.py'),1)
        self.assertIn('SIGABRT',output.getvalue())
        self.assertIn('No native pass',output.getvalue())
        self.assertIn('WindowServer',output.getvalue())

    def test_other_signal_is_not_misclassified_as_gui_failure(self):
        output=io.StringIO()
        with patch('appkit_smoke_runner.subprocess.run',return_value=subprocess.CompletedProcess([],-signal.SIGTERM)),contextlib.redirect_stderr(output):
            self.assertEqual(run_native('/tmp/smoke.py'),1)
        self.assertIn('SIGTERM',output.getvalue()); self.assertNotIn('WindowServer',output.getvalue())

    def test_success_and_timeout(self):
        with patch('appkit_smoke_runner.subprocess.run',return_value=subprocess.CompletedProcess([],0)):
            self.assertEqual(run_native('/tmp/smoke.py'),0)
        with patch('appkit_smoke_runner.subprocess.run',side_effect=subprocess.TimeoutExpired('smoke',120)),contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(run_native('/tmp/smoke.py'),1)
        self.assertIn('timed out',output.getvalue())
