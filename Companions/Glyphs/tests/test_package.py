# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import json
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
            self.assertEqual(a['build'],2)
            self.assertIn('build2',a['artifacts'][0]['path'])
            self.assertEqual((first/a['artifacts'][0]['path']).read_bytes(),(second/b['artifacts'][0]['path']).read_bytes())
            self.assertEqual(verify(first),a)
            self.assertFalse(a['engine']['bundled'])
            self.assertEqual(a['qualification']['nativeTestedBuilds'],[])
            self.assertEqual(a['artifacts'][0]['signing']['status'],'unsigned')
            self.assertFalse(any('__pycache__' in item['path'] for item in a['payload']))
            for name in ['LICENSE-APACHE','LICENSE-MIT','THIRD_PARTY_NOTICES','GlyphsSDK-LICENSE.txt','GlyphsSDK-SOURCE.json','sbom.spdx.json']:
                self.assertTrue((first/'Beztrace.glyphsPlugin/Contents/Resources'/name).exists())
            with self.assertRaises(ValueError): build(first)

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
