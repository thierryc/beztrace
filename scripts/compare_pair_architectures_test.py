#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import json
from pathlib import Path
import tempfile
import unittest
from compare_pair_architectures import compare


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.roots = [Path(self.temp.name) / name for name in ['arm', 'intel']]
        for root in self.roots:
            result = root / 'results/control'
            result.mkdir(parents=True)
            (root / 'receipt.json').write_text(json.dumps({'engineSHA256': 'local', 'cases': [{'case': 'control'}]}))
            (result / 'comparison.json').write_text(json.dumps({'sourceHashes': ['a', 'b'], 'inputFiles': [], 'options': {}, 'strategy': 'direct'}))
            (result / 'recommended.master-set.json').write_text('{"x":1.000000000001}')

    def test_identical_artifacts(self):
        self.assertTrue(compare(*self.roots)['byteIdentical'])

    def test_one_bit_scale_difference_is_not_rounded_away(self):
        (self.roots[1] / 'results/control/recommended.master-set.json').write_text('{"x":1.000000000002}')
        report = compare(*self.roots)
        self.assertFalse(report['byteIdentical'])
        self.assertEqual(report['cases'][0]['differentFiles'], ['recommended.master-set.json'])

    def test_missing_candidate_is_a_failure(self):
        (self.roots[1] / 'results/control/recommended.master-set.json').unlink()
        self.assertFalse(compare(*self.roots)['byteIdentical'])

    def test_changed_source_is_an_invalid_comparison(self):
        file = self.roots[1] / 'results/control/comparison.json'
        report = json.loads(file.read_text())
        report['sourceHashes'][0] = 'different'
        file.write_text(json.dumps(report))
        with self.assertRaises(ValueError):
            compare(*self.roots)


if __name__ == '__main__':
    unittest.main()
