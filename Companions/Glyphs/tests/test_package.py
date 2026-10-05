# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import json
from datetime import datetime
import importlib.util
import os
import py_compile
import zipfile
from pathlib import Path
import sys
import tempfile
import unittest
from test_contract import ROOT
sys.path.insert(0,str(ROOT/'scripts'))
from package import build
from verify_package import verify


class PackageTests(unittest.TestCase):
    def test_reproducible_archives_and_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            first,second=Path(tmp)/'first',Path(tmp)/'second'
            a,b=build(first),build(second)
            self.assertEqual(a,b)
            self.assertEqual(a['build'],14)
            self.assertIn('build14',a['artifacts'][0]['path'])
            self.assertEqual((first/a['artifacts'][0]['path']).read_bytes(),(second/b['artifacts'][0]['path']).read_bytes())
            self.assertEqual(verify(first),a)
            self.assertFalse(a['engine']['bundled'])
            self.assertEqual(a['engine']['versions'],[
                '0.1.0','0.1.1-dev.1','0.1.1-dev.2','0.1.1-dev.3','0.1.1-dev.4','0.1.1'
            ])
            self.assertEqual(a['qualification']['nativeTestedBuilds'],[])
            self.assertEqual(a['artifacts'][0]['signing']['status'],'unsigned')
            self.assertFalse(any('__pycache__' in item['path'] for item in a['payload']))
            for name in ['LICENSE-APACHE','LICENSE-MIT','THIRD_PARTY_NOTICES','GlyphsSDK-LICENSE.txt','GlyphsSDK-SOURCE.json','sbom.spdx.json']:
                self.assertTrue((first/'Beztrace.glyphsPlugin/Contents/Resources'/name).exists())
            with self.assertRaises(ValueError): build(first)

    def test_build_timestamp_invalidates_same_size_external_bytecode_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'build'; manifest=build(directory)
            with zipfile.ZipFile(directory/manifest['artifacts'][0]['path']) as archive:
                stamp=archive.getinfo('Beztrace.glyphsPlugin/Contents/Resources/beztrace_companion/ui.py').date_time
            old_stamp=int(datetime(2026,9,27).timestamp())
            new_stamp=int(datetime(*stamp).timestamp())
            module_path=Path(tmp)/'cached_companion.py'
            module_path.write_text("loaded_build = 12\n")
            os.utime(module_path,(old_stamp,old_stamp))
            py_compile.compile(str(module_path),doraise=True)
            # Updating a bundle does not clear Glyphs' separate PythonCache.
            module_path.write_text("loaded_build = 13\n")
            os.utime(module_path,(new_stamp,new_stamp))
            spec=importlib.util.spec_from_file_location('cached_companion',module_path)
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            self.assertEqual(module.loaded_build,manifest['build'])

    def test_tampered_payload_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'build'; build(directory)
            (directory/'Beztrace.glyphsPlugin/Contents/Resources/plugin.py').write_text('tampered')
            with self.assertRaises(ValueError): verify(directory)

    def test_tampered_archive_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'build'; manifest=build(directory)
            (directory/manifest['artifacts'][0]['path']).write_bytes(b'invalid')
            with self.assertRaises(ValueError): verify(directory)

    def test_engine_schema_is_unchanged(self):
        bundle=ROOT/'Beztrace.glyphsPlugin/Contents/Resources/trace-result-v1.schema.json'
        self.assertEqual(bundle.read_bytes(),(ROOT.parents[1]/'Schemas/trace-result-v1.schema.json').read_bytes())


if __name__=='__main__': unittest.main()
