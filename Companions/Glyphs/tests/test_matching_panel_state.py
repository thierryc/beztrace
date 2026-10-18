# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import json
import unittest
from test_contract import ROOT
from beztrace_companion.matching_panel_state import (initial_master_pair,next_action,point_budget,
    MODE_LABELS,MATCH_SOURCE_MODES,visible_settings,preview_actions)
from beztrace_companion.matching_preview import payload,commands


class MatchingPanelStateTests(unittest.TestCase):
    def test_four_modes_route_without_changing_matching_api_modes(self):
        self.assertEqual(len(MODE_LABELS),4)
        self.assertEqual(MATCH_SOURCE_MODES,(None,2,1,0))

    def test_inspector_contains_only_relevant_controls(self):
        self.assertIn('accuracy',visible_settings(0))
        self.assertIn('raster',visible_settings(0))
        self.assertNotIn('fit',visible_settings(0))
        for mode in (1,2,3):
            self.assertTrue({'fit','nodes','smooth','actions'} <= visible_settings(mode))
            self.assertNotIn('repair',visible_settings(mode,hoi=False))
            self.assertIn('repair',visible_settings(mode,hoi=True))
        self.assertNotIn('raster',visible_settings(3,hoi=True,repair=True,shared=True))
        self.assertNotIn('policy',visible_settings(1,shared=True))
        self.assertNotIn('pairs',visible_settings(1,manual=True))
        self.assertNotIn('repair',visible_settings(0,hoi=True))
        self.assertIn('raster',visible_settings(2))
        self.assertIn('policy',visible_settings(2))
        self.assertIn('extra',visible_settings(2,shared=True))
        self.assertNotIn('extra',visible_settings(2,shared=False))
        self.assertNotIn('kink',visible_settings(2,hoi=True,repair=False))
        self.assertIn('kink',visible_settings(2,hoi=True,repair=True))
        self.assertNotIn('pairs',visible_settings(2))
        self.assertIn('pairs',visible_settings(2,manual=True))
        self.assertNotIn('pairs',visible_settings(3,manual=True,review=True))
        self.assertNotIn('manual',visible_settings(3,review=True))
        self.assertNotIn('extra',visible_settings(3,review=True,shared=True))

    def test_update_and_apply_are_independent_and_fail_closed(self):
        self.assertEqual(preview_actions(True,False,False,False),dict(update=True,apply=False))
        self.assertEqual(preview_actions(True,False,True,True),dict(update=False,apply=True))
        self.assertEqual(preview_actions(True,False,True,False),dict(update=False,apply=False))
        for busy,usable in ((True,True),(False,False)):
            for current in (True,False):
                self.assertEqual(preview_actions(usable,busy,current,True),dict(update=False,apply=False))
    def test_strict_reference_budget_counts_on_curves_separately_from_controls(self):
        reference=dict(contours=[dict(nodes=[dict(type='line') for _ in range(22)]+
            [dict(type='offcurve') for _ in range(26)])])
        self.assertEqual(point_budget(reference,0,48,1),
            dict(maxAdditionalOnCurveNodes=0,maxOnCurveNodes=22,maxNodes=48))
        self.assertEqual(point_budget(reference,2,54,1)['maxOnCurveNodes'],24)
        self.assertEqual(point_budget(reference,0,48,2)['maxOnCurveNodes'],48)
    def test_active_master_is_target_from_either_master(self):
        self.assertEqual(initial_master_pair(['light','bold'],'light'),(1,0))
        self.assertEqual(initial_master_pair(['light','bold'],'bold'),(0,1))

    def test_previous_selection_is_reference_when_available(self):
        self.assertEqual(initial_master_pair(['a','b','c'],'c','a'),(0,2))
        self.assertEqual(initial_master_pair(['a','b','c'],'c','removed'),(1,2))
        self.assertEqual(initial_master_pair(['a','b','c'],'c','c'),(1,2))

    def test_apply_is_primary_only_after_verified_processing(self):
        self.assertEqual(next_action(True,False,False),'process')
        self.assertEqual(next_action(True,False,True),'apply')
        self.assertEqual(next_action(True,True,True),'processing')
        self.assertEqual(next_action(False,False,True),'unavailable')

    def test_unprocessed_shifted_start_midpoint_shows_target_without_collapsing(self):
        request=json.loads((ROOT.parents[1]/'Tests/Fixtures/matching/v1/shifted-start.json').read_text())
        context=dict(outlines=[request[r]['outline'] for r in ('reference','target')],axis=dict(locations=[100,900]))
        original=copy.deepcopy(context)
        for locations in ([100,900],[900,100]):
            context['axis']['locations']=locations
            for factor in (0,.5,1):
                preview=payload(context,factor=factor)
                self.assertEqual(preview['after'],commands(request['target']['outline']['contours']))
                self.assertFalse(preview['processed']); self.assertFalse(preview['links'])
        self.assertEqual(context['outlines'],original['outlines'])


if __name__=='__main__': unittest.main()
