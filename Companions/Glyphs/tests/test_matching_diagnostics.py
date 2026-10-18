# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import json
import threading
import unittest
from unittest.mock import patch
from test_matching import ENGINE, result, Host
from beztrace_companion import matching_contract as contract
from beztrace_companion.matching_preview import payload
from beztrace_companion.contract import CompanionError, validate_schema
from pathlib import Path


class MatchingDiagnosticsTests(unittest.TestCase):
    def test_error_details_survive_transport_and_highlight_original_segments(self):
        diagnostic=dict(code='self-intersection',message='self-intersection',stage='input',role='reference',
            masterID='regular',locations=[dict(contour=0,segment=0,startNode=0,endNode=1,parameterRange=[0,1]),
            dict(contour=0,segment=2,startNode=2,endNode=3,parameterRange=[0,1])],coordinates=[40,40],
            classification='crossing',approximationTolerance=.05,existedBeforeFitting=True,blocking=True)
        error=contract.engine_failure(json.dumps(dict(error=dict(message='Reference crossing',diagnostic=diagnostic))).encode())
        self.assertIsInstance(error,CompanionError); self.assertEqual(error.diagnostic,diagnostic)
        packet=result(); host=Host(packet); ctx=host.context(None,'A','0'); before=copy.deepcopy(ctx['outlines'])
        view=payload(ctx,diagnostic=error.diagnostic)
        self.assertEqual(view['diagnosticMarkers'],[(40,40)])
        self.assertEqual(len(view['diagnosticHighlights']),4)
        self.assertEqual(ctx['outlines'],before)
        error.diagnostic['coordinates'][0]=999
        self.assertEqual(diagnostic['coordinates'],[40,40])
        fitted=dict(diagnostic,stage='fitted')
        self.assertFalse(payload(ctx,diagnostic=fitted)['diagnosticHighlights'])
        self.assertFalse(payload(ctx,diagnostic=fitted)['diagnosticMarkers'])
    def test_legacy_errors_and_invalid_evidence_cannot_create_preview_markers(self):
        old=contract.engine_failure(b'{"error":{"message":"Legacy refusal"}}')
        self.assertEqual(str(old),'Legacy refusal'); self.assertIsNone(old.diagnostic)
        invalid=contract.engine_failure(b'{"error":{"message":"Refusal","diagnostic":{"coordinates":[1e100,2]}}}')
        self.assertIsNone(invalid.diagnostic)
    def test_fitting_evidence_survives_transport_without_an_accepted_preview(self):
        diagnostic=dict(code='fixed-structure-fit',message='Fit unresolved',stage='fitting',role='target',
            masterID='bold',mode='trace-to-reference',blocking=True,section=8,measuredDeviation=1.05,
            allowedDeviation=.9375,cause='fit-not-established',existedBeforeFitting=False,
            locations=[dict(contour=0,segment=8,startNode=18,endNode=19,parameterRange=[0,1])],
            boundarySpan=dict(contour=0,startPoint=3113,endPoint=671,fractions=[.36,.42]))
        error=contract.engine_failure(json.dumps(dict(error=dict(message='Fit unresolved',diagnostic=diagnostic))).encode())
        self.assertEqual(error.diagnostic,diagnostic)
        host=Host(result()); view=payload(host.context(None,'A','0'),diagnostic=error.diagnostic)
        self.assertFalse(view['diagnosticHighlights']); self.assertFalse(view['diagnosticMarkers'])
    def test_read_only_preflight_before_target_artwork_and_preserved_limits(self):
        packet=result(); reference=packet['sourceMasters'][0]
        request=dict(schemaVersion=1,unitsPerEm=1000,reference=reference,options=packet['options'])
        before=copy.deepcopy(request)
        report=contract.reference_preflight(str(ENGINE),request)
        self.assertTrue(report['eligible']); self.assertFalse(report['rasterTopologyChecked'])
        self.assertEqual(request,before)
        blocked=copy.deepcopy(request); blocked['options']['maxNodes']=3
        held=contract.reference_preflight(str(ENGINE),blocked)
        self.assertFalse(held['eligible']); self.assertTrue(any(d['code']=='node-budget' for d in held['diagnostics']))
        self.assertNotIn('outline',held)
        with patch.object(contract,'capabilities',return_value={'referencePreflightVersion':0}):
            with self.assertRaisesRegex(CompanionError,'preflight support'):
                contract.reference_preflight(str(ENGINE),request)
    def test_preflight_schema_parity(self):
        resources=Path(contract.__file__).parents[1]
        repo=resources.parents[4]
        for name in ('match-diagnostic-v1.schema.json','match-preflight-request-v1.schema.json','match-preflight-result-v1.schema.json'):
            self.assertEqual((resources/name).read_bytes(),(repo/'Schemas'/name).read_bytes())
