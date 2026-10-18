# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Real-engine preparation and fail-closed smoothing transport; no native font."""
import copy
import json
import threading
import unittest
from unittest.mock import patch
from test_matching import Host, finish, ENGINE
from beztrace_companion import matching, matching_contract
from beztrace_companion.contract import CompanionError


def outlines():
    values=[(0,0,'line',False),(100,0,'line',True),(130,0,'offcurve',False),
            (150,30,'offcurve',False),(150,50,'curve',True),(150,100,'line',False),(0,100,'line',False)]
    a=dict(contours=[dict(closed=True,nodes=[dict(x=x,y=y,type=k,smooth=s) for x,y,k,s in values])])
    b=copy.deepcopy(a); b['contours'][0]['nodes'][2]['x']+=.5; b['contours'][0]['nodes'][3]['y']-=.5
    return a,b


class MatchingSmoothingTests(unittest.TestCase):
    def prepare(self,tolerance=1):
        a,b=outlines()
        host=Host(dict(sourceMasters=[dict(id='0',outline=a),dict(id='1',outline=b)]))
        job=matching.prepare_match(host.font,'A','0',settings=dict(smoothJoins=True,repairHOI=False,fitTolerance=tolerance),
            source_mode=3,engine=str(ENGINE),_host=host)
        return host,job

    def test_prepare_preview_apply_and_export_share_the_verified_geometry(self):
        host,job=self.prepare(); before=[host.fingerprint(l) for l in host.layers]
        plan=finish(job); packet=plan.result
        self.assertEqual([host.fingerprint(l) for l in host.layers],before)
        self.assertEqual(packet['jointSmoothing']['status'],'smoothed')
        self.assertLessEqual(packet['jointSmoothing']['proposalDeviation']['upperBound'],1)
        self.assertEqual(packet['reference']['outline'],outlines()[0])
        self.assertFalse(packet['interpolation']['nativeHOIVerified']); self.assertIsNone(plan.hoi)
        self.assertEqual(matching_contract.parse_master_set(matching.export_match(plan)),packet)
        matching.apply_match(plan)
        self.assertEqual(host.layers[0].shapes,outlines()[0]['contours'])
        self.assertEqual(host.layers[1].shapes,packet['target']['outline']['contours'])
        self.assertEqual(host.events,['begin','end','redraw'])

    def test_refusal_leaves_both_masters_intact_and_has_no_apply_plan(self):
        host,job=self.prepare(.01); before=[host.fingerprint(l) for l in host.layers]
        with self.assertRaises(matching_contract.MatchingDiagnosticError) as caught: finish(job)
        self.assertEqual(caught.exception.diagnostic['code'],'joint-smoothing-refused')
        self.assertEqual(caught.exception.diagnostic['allowedDeviation'],.01)
        self.assertEqual([host.fingerprint(l) for l in host.layers],before); self.assertEqual(host.events,[])

    def test_engine_upgrade_is_required_before_sending_new_option(self):
        with patch.object(matching_contract,'capabilities',return_value={'engineVersion':'0.2.1'}), \
                patch.object(matching_contract,'run_process') as process:
            with self.assertRaisesRegex(CompanionError,'verified joint smoothing'):
                matching_contract.match(str(ENGINE),dict(options=dict(smoothJoins=True)),threading.Event())
            process.assert_not_called()

    def test_unverified_over_budget_or_non_handle_reports_are_rejected(self):
        _,job=self.prepare(); original=finish(job).result
        for mutation in (lambda p:p.pop('jointSmoothing'),
                         lambda p:p['jointSmoothing']['proposalDeviation'].update(upperBound=2),
                         lambda p:p['jointSmoothing']['changedHandles'][0].update(node=0),
                         lambda p:p['interpolation'].update(sampleCount=101)):
            packet=copy.deepcopy(original); mutation(packet)
            with self.assertRaises(CompanionError): matching_contract.parse_master_set(json.dumps(packet).encode())
        for value in (1,'true',None):
            with self.assertRaises(CompanionError): matching.options(dict(smoothJoins=value))

    def test_import_reproduces_smoothed_original_source_contract(self):
        _,job=self.prepare(); packet=finish(job).result
        host=Host(packet)
        imported=finish(matching.prepare_match(host.font,'A','0',settings=dict(repairHOI=False),
            imported=matching_contract.export_bytes(packet),confirm_axis=True,engine=str(ENGINE),_host=host))
        self.assertEqual(imported.result['reference'],packet['reference'])
        self.assertEqual(imported.result['target'],packet['target'])
        self.assertEqual(imported.result['jointSmoothing'],packet['jointSmoothing'])
        self.assertTrue(imported.settings['smoothJoins'])


if __name__=='__main__': unittest.main()
