# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'))
from beztrace_companion.contract import (CompanionError, combined_warning, parse_result, place, segments,
                                         signed_area, tight_bounds, validate_schema)


def contour(points, kinds=None):
    kinds = kinds or ['line'] * len(points)
    return dict(closed=True,nodes=[dict(x=x,y=y,type=t,smooth=False) for (x,y),t in zip(points,kinds)])


def sample():
    # Fully valid synthetic contract; the integration tests use released output.
    return dict(schemaVersion=1,engine=dict(name='beztrace',version='0.1.0',portSourceRevision='a'*40),
        source=dict(sha256=hashlib.sha256(b'image').hexdigest(),format='png',width=100,height=100,usedAlphaMask=False),
        resolvedOptions=dict(profile='clean-generated',thresholdMethod='automatic',threshold=127,invert=False,
            minimumContourArea=100,targetHeight=1088,accuracy=2,smoothing=1,cornerThresholdDegrees=12,
            grid=2,structureGrid=0,refineRaster=True,rtlStart=False,diagnostics='none'),
        pathDataVersion=2,metadataPolicy='preserve',
        paths=[contour([(10,20),(10,120),(110,120),(110,20)])],bounds=[10,20,110,120],placement=None,
        statistics=dict(contourCount=1,nodeCount=4,lineCount=4,curveCount=0,offCurveCount=0),timingsMs={},warnings=[])


class ContractTests(unittest.TestCase):
    def decode(self, data):
        return parse_result(json.dumps(data).encode(),b'image')

    def test_complete_contract(self):
        self.assertEqual(self.decode(sample()),sample())

    def test_engine_and_application_warnings_are_combined(self):
        result=sample(); result['warnings']=['Grid 8 was skipped for 1 contour to preserve valid geometry.']
        self.assertEqual(combined_warning(sample()),None)
        self.assertEqual(combined_warning(result),'Grid 8 was skipped for 1 contour to preserve valid geometry.')
        self.assertEqual(combined_warning(result,'Paths applied; redraw failed.'),
                         'Grid 8 was skipped for 1 contour to preserve valid geometry. Paths applied; redraw failed.')

    def test_schema_keywords_are_all_implemented(self):
        schema=json.loads((ROOT/'Beztrace.glyphsPlugin/Contents/Resources/trace-result-v1.schema.json').read_text())
        known={'$schema','$id','title','$defs','$ref','type','additionalProperties','required','properties','const','enum',
               'pattern','minimum','maximum','exclusiveMinimum','exclusiveMaximum','minItems','maxItems','items','prefixItems','oneOf'}
        def walk(rule):
            self.assertFalse(set(rule)-known)
            for key in ('properties','$defs'):
                for child in rule.get(key,{}).values(): walk(child)
            for key in ('items','additionalProperties'):
                if isinstance(rule.get(key),dict): walk(rule[key])
            for key in ('prefixItems','oneOf'):
                for child in rule.get(key,[]): walk(child)
        walk(schema)
        self.assertEqual(schema,json.loads((ROOT.parents[1]/'Schemas/trace-result-v1.schema.json').read_text()))

    def test_all_required_fields(self):
        for key in sample():
            with self.subTest(key=key):
                data=sample(); del data[key]
                with self.assertRaises(CompanionError): self.decode(data)

    def test_invalid_variants(self):
        edits=[('schemaVersion',2),('schemaVersion',True),('pathDataVersion',1),('metadataPolicy','replace'),
               ('paths',[]),('bounds',None),('warnings',[1]),('extra',1)]
        for key,value in edits:
            with self.subTest(key=key,value=value):
                data=sample(); data[key]=value
                with self.assertRaises(CompanionError): self.decode(data)

    def test_engine_source_and_neutral_checks(self):
        for section,key,value in [('engine','version','0.2.0'),('engine','name','other'),('source','sha256','b'*64),
                                  ('source','width',4097),('resolvedOptions','targetHeight',700),('statistics','nodeCount',3)]:
            with self.subTest(section=section,key=key):
                data=sample(); data[section][key]=value
                with self.assertRaises(CompanionError): self.decode(data)

    def test_nonfinite_boolean_and_excessive_coordinates(self):
        for value in [float('nan'),float('inf'),True,1e8]:
            data=sample(); data['paths'][0]['nodes'][0]['x']=value
            with self.assertRaises(CompanionError): self.decode(data)

    def test_malformed_duplicate_and_deep_json(self):
        for data in [b'',b'no json',b'{"a":1,"a":2}',b'\xff',b'['*2000+b']'*2000]:
            with self.assertRaises(CompanionError): parse_result(data,b'image')

    def test_wrong_bounds_and_open_paths(self):
        data=sample(); data['bounds'][0]=0
        with self.assertRaises(CompanionError): self.decode(data)
        data=sample(); data['paths'][0]['closed']=False
        with self.assertRaises(CompanionError): self.decode(data)

    def test_cubic_with_closing_handles(self):
        path=contour([(0,0),(100,0),(100,100),(0,100)],['curve','line','offcurve','offcurve'])
        parts=list(segments(path))
        self.assertEqual(len(parts),2)
        self.assertEqual(len(parts[-1][1]),2)
        self.assertEqual(parts[-1][-1],path['nodes'][0])
        self.assertEqual(tight_bounds([path]),[0,0,100,75])
        self.assertAlmostEqual(signed_area(path),6000)

    def test_rotated_start_preserves_closure(self):
        path=contour([(0,0),(100,0),(100,100),(0,100)],['curve','line','offcurve','offcurve'])
        area=signed_area(path)
        for i in range(4):
            rotated=copy.deepcopy(path); rotated['nodes']=path['nodes'][i:]+path['nodes'][:i]
            self.assertAlmostEqual(signed_area(rotated),area)
            self.assertEqual(tight_bounds([rotated]),[0,0,100,75])

    def test_invalid_cubic_sequences(self):
        for types in [['line','offcurve','line','line'],['curve','line','line','line'],['line','offcurve','offcurve','offcurve']]:
            with self.assertRaises(CompanionError): list(segments(contour([(0,0),(10,0),(10,10),(0,10)],types)))

    def test_placement_once_preserves_handles_and_direction(self):
        data=sample(); data['paths']=[contour([(0,0),(100,0),(100,100),(0,100)],['curve','line','offcurve','offcurve'])]
        data['paths'][0]['nodes'][0]['smooth']=True
        data['bounds']=tight_bounds(data['paths'])
        paths=place(data,150,-50,25)
        self.assertEqual(tight_bounds(paths),[25,-50,225,100])
        self.assertEqual(paths[0]['nodes'][2]['y'],150)
        self.assertTrue(paths[0]['nodes'][0]['smooth'])
        self.assertAlmostEqual(signed_area(paths[0]),4*signed_area(data['paths'][0]))
        self.assertEqual(place(data,150,-50,25),paths)
        self.assertEqual(data['paths'][0]['nodes'][0]['x'],0)
        data['placement']={}
        with self.assertRaises(CompanionError): place(data)

    def test_holes_keep_opposed_winding(self):
        data=sample(); hole=contour([(30,40),(90,40),(90,100),(30,100)])
        data['paths'].append(hole)
        paths=place(data,700)
        self.assertLess(signed_area(paths[0])*signed_area(paths[1]),0)

    def test_invalid_placement(self):
        for args in [(0,0,0),(-1,0,0),(float('inf'),0,0),(700,float('nan'),0),(700,0,1e8)]:
            with self.assertRaises(CompanionError): place(sample(),*args)


if __name__=='__main__': unittest.main()
