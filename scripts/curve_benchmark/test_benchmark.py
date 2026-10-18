# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import json
import unittest
from pathlib import Path
import numpy as np
import run


class BenchmarkTests(unittest.TestCase):
    def test_exact_subdivision_preserves_geometry(self):
        c=[0,0,30,80,70,-40,100,0];a,b=run.split(c)
        np.testing.assert_allclose(run.sample(a,65),run.sample(c,129)[:65],atol=1e-12)
        np.testing.assert_allclose(run.sample(b,65),run.sample(c,129)[64:],atol=1e-12)

    def test_graph_can_beat_greedy_on_same_edges(self):
        edges=[dict(start=a,end=b,cost=1,error=0,key=f'{a}-{b}') for a,b in [(0,1),(0,2),(1,4),(2,3),(3,4)]]
        self.assertEqual(len(run.select(4,edges,'greedy')),3)
        self.assertEqual(len(run.select(4,edges,'graph')),2)

    def test_roundtrip_preserves_cyclic_nodes_and_flags(self):
        o=run.outline([run.ellipse(200,300,.3)])
        self.assertEqual(o,run.outline(run.spans(o)))

    def test_kink_controls_are_real_and_ratio_repair_preserves_reference(self):
        cases,_=run.corpus()
        for case in cases:
            if not case['id'].startswith('kink-'):continue
            self.assertGreater(run.kink_metric(case['outlines']),.05)
            repaired=run.shared_ratio_trial(case['outlines'])
            self.assertEqual(repaired[0],case['outlines'][0])
            for f in np.linspace(0,1,21):self.assertLess(run.kink_metric(repaired,float(f)),1e-10)

    def test_protected_extrema_remain_job_boundaries(self):
        cases,_=run.corpus();jobs,groups=run.make_jobs(cases,6)
        lookup={g['id']:g for g in groups}
        for j in jobs:
            self.assertFalse(any(j['start']<i<j['end'] for i in lookup[j['group']]['locks']))

    def test_verifier_analytic_controls(self):
        binary=run.ROOT/'.build/curve-benchmark-tools/driver'
        if not binary.exists():self.fail('Build the Swift driver before testing')
        self.assertEqual(json.loads(run.command([binary,'selftest'],payload={})),{'passed':3})


if __name__=='__main__':unittest.main()
