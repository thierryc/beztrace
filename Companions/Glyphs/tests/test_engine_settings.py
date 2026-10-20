# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from test_contract import ROOT
from beztrace_companion.contract import CompanionError
from beztrace_companion.engine import default_engine
from beztrace_companion.engine_settings import settings_path, selected_engine, save_user_engine


class EngineSettingsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name).resolve()
        self.settings = settings_path(self.home)
        self.engine = self.home / 'Independent Engine/bin/beztrace'
        self.engine.parent.mkdir(parents=True)
        self.engine.write_bytes(b'#!/bin/sh\nexit 0\n')
        self.engine.chmod(0o755)

    def write(self, value):
        self.settings.parent.mkdir(parents=True, exist_ok=True)
        self.settings.write_text(json.dumps(value))

    def test_absent_settings_leave_fallback_and_files_untouched(self):
        self.assertEqual(selected_engine('/fallback', self.home), '/fallback')
        self.assertFalse(self.settings.parent.exists())

    def test_user_then_managed_then_default_priority(self):
        self.write(dict(schemaVersion=1, managedEngine='/managed'))
        self.assertEqual(default_engine('/packaged/plugin.py', home=self.home), '/managed')
        self.write(dict(schemaVersion=1, managedEngine='/managed', userEngine='/independent'))
        self.assertEqual(default_engine('/packaged/plugin.py', home=self.home), '/independent')
        # Explicit paths are retained even when missing; launch reports the error.
        self.assertFalse(Path('/independent').exists())

    def test_selection_persists_without_replacing_engine_or_managed_data(self):
        original = self.engine.read_bytes()
        self.write(dict(schemaVersion=1, managedEngine='/managed', extension={'preserve': True}))
        save_user_engine(str(self.engine), self.home)
        self.assertEqual(json.loads(self.settings.read_text()),
                         dict(schemaVersion=1, managedEngine='/managed', userEngine=str(self.engine),
                              extension={'preserve': True}))
        self.assertEqual(selected_engine('/fallback', self.home), str(self.engine))
        self.assertEqual(self.engine.read_bytes(), original)
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.settings.parent.glob('.engine-settings-*')), [])

    def test_invalid_existing_configuration_is_preserved_and_never_falls_back(self):
        for value in [[], dict(schemaVersion=True), dict(schemaVersion=2),
                      dict(schemaVersion=1, userEngine='relative'),
                      dict(schemaVersion=1, managedEngine=None),
                      dict(schemaVersion=1, userEngine='/bad\0path')]:
            with self.subTest(value=value):
                self.write(value)
                original = self.settings.read_bytes()
                with self.assertRaises(CompanionError): selected_engine('/fallback', self.home)
                with self.assertRaises(CompanionError): save_user_engine(str(self.engine), self.home)
                self.assertEqual(self.settings.read_bytes(), original)

    def test_corrupt_and_oversized_files_are_preserved(self):
        self.settings.parent.mkdir(parents=True)
        for content in [b'{', b'\xff', b'x' * 16385]:
            self.settings.write_bytes(content)
            with self.assertRaises(CompanionError): save_user_engine(str(self.engine), self.home)
            self.assertEqual(self.settings.read_bytes(), content)

    def test_symlinked_configuration_is_not_read_or_overwritten(self):
        target = self.home / 'external.json'
        target.write_text('{"schemaVersion":1}')
        self.settings.parent.mkdir(parents=True)
        self.settings.symlink_to(target)
        with self.assertRaises(CompanionError): selected_engine('/fallback', self.home)
        with self.assertRaises(CompanionError): save_user_engine(str(self.engine), self.home)
        self.assertTrue(self.settings.is_symlink())
        self.assertEqual(target.read_text(), '{"schemaVersion":1}')

    def test_invalid_executable_does_not_create_configuration(self):
        for executable in ['relative', '/missing/engine', str(self.home), '/bad\0path']:
            with self.assertRaises(CompanionError): save_user_engine(executable, self.home)
            self.assertFalse(self.settings.exists())

    def test_changed_configuration_aborts_write(self):
        self.write(dict(schemaVersion=1))
        original = self.settings.read_bytes()
        with patch('beztrace_companion.engine_settings._read', side_effect=[original, b'changed']):
            with self.assertRaisesRegex(CompanionError, 'changed'):
                save_user_engine(str(self.engine), self.home)
        self.assertEqual(self.settings.read_bytes(), original)
        self.assertEqual(list(self.settings.parent.glob('.engine-settings-*')), [])


if __name__ == '__main__':
    unittest.main()
