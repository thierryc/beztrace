#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Compare frozen research and sequential-hybrid runs without changing either."""
import argparse
import collections
import json
import statistics
from pathlib import Path


def compare(before, after):
    def read(root, name):
        return json.loads((root / name).read_text())
    old_input, new_input = read(before, 'inputs.json'), read(after, 'inputs.json')
    assert old_input == new_input, 'Corpus, spans, tolerances or timing configuration changed'
    assert read(before, 'cases.json') == read(after, 'cases.json'), 'Source outlines changed'
    old_candidates = read(before, 'swift-candidates.json') + read(before, 'kurbo-candidates.json')
    new_candidates = read(after, 'swift-candidates.json') + read(after, 'kurbo-candidates.json')
    def proposals(candidates):
        return {(c['id'], c['tolerance'], c['method']): (c.get('curve'), c['line'])
                for c in candidates if c['method'] in {'least-squares-8', 'least-squares-refined', 'levien-kurbo-0.13.1'}}
    assert proposals(old_candidates) == proposals(new_candidates), 'Historical proposal geometry changed'
    old_results, new_results = read(before, 'results.json'), read(after, 'results.json')
    old_index = {r['id']: r for r in old_results}
    for r in new_results:
        if r['id'] in old_index:
            old = old_index[r['id']]
            assert old['outlines'] == r['outlines'], ('Historical selection changed', r['id'])
            assert old['checks']['valid'] == r['checks']['valid'], ('Historical acceptance changed', r['id'])
    jobs = {j['id']: j for j in new_input['jobs']}
    rows = []
    for tolerance in new_input['tolerances']:
        row = {'tolerance': tolerance, 'methods': {}}
        for method in ['least-squares-refined', 'hybrid', 'refined-swift-verified', 'hybrid-swift']:
            rs = [r for r in new_results if r['tolerance'] == tolerance and r['method'] == method and r['selector'] == 'greedy']
            passed = [r for r in rs if r['checks']['valid']]
            entry = {'accepted': len(passed), 'nodesOnAccepted': sum(r['outputNodes'] for r in passed),
                     'refusedCases': [r['case'] for r in rs if not r['checks']['valid']]}
            assert entry['refusedCases'] == ['kink-strong'], 'Unexpected refusal regression'
            if method.endswith('-verified') or method == 'hybrid-swift':
                calls = [c for c in new_candidates if c['method'] == method and c['tolerance'] == tolerance and jobs[c['id']]['end'] - jobs[c['id']]['start'] > 1]
                times = sorted(statistics.median(c['timesMs']) for c in calls)
                entry.update(multiSpanAttempts=len(times), medianPipelineMs=statistics.median(times),
                             p95PipelineMs=times[int(.95 * (len(times) - 1))], sumMedianPipelineMs=sum(times))
            row['methods'][method] = entry
        hybrid = row['methods']['hybrid-swift']
        assert hybrid['nodesOnAccepted'] <= row['methods']['least-squares-refined']['nodesOnAccepted'], 'Node regression'
        row['proposalMethods'] = dict(collections.Counter(c.get('selectedFitter', 'refused') for c in new_candidates if c['method'] == 'hybrid-swift' and c['tolerance'] == tolerance))
        rows.append(row)
    return {'identicalInputs': True, 'historicalProposalGeometryUnchanged': True, 'historicalOutputsAndAcceptanceUnchanged': True,
            'timingScope': 'Native Swift full source preparation, sampling, fit and verifier; multi-span attempts, median of 11 timed calls after 2 warmups. Raw legacy proposal timings excluded.',
            'comparisons': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.before, args.after)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result, indent=2))
