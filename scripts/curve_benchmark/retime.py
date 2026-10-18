#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Repeat the comparable native Swift timing workload after other checks finish."""
import argparse
import hashlib
import json
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    report = args.report.resolve()
    receipt = json.loads((report / 'receipt.json').read_text())
    driver = ROOT / '.build/curve-benchmark-tools/driver'
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    assert digest(driver) == receipt['binaries'][str(driver.relative_to(ROOT))], 'Driver changed'
    assert all(digest(ROOT / path) == value for path, value in receipt['coreFiles'].items()), 'Core changed'
    payload = json.loads((report / 'inputs.json').read_text())
    payload['jobs'] = [j for j in payload['jobs'] if not j['line'] and j['end'] - j['start'] > 1]
    (report / 'isolated-timing-inputs.json').write_text(json.dumps(payload, indent=2) + '\n')
    started = time.monotonic()
    result = subprocess.run([str(driver), 'fit'], input=json.dumps(payload), text=True, capture_output=True, check=True)
    candidates = json.loads(result.stdout)
    (report / 'isolated-timing-candidates.json').write_text(result.stdout + '\n')
    old = {(c['id'], c['tolerance'], c['method']): c for c in json.loads((report / 'swift-candidates.json').read_text())}
    for c in candidates:
        previous = old[c['id'], c['tolerance'], c['method']]
        assert all(c.get(k) == previous.get(k) for k in ['curve', 'line', 'selectedFitter']), 'Geometry changed on timing repeat'
    rows = []
    for tolerance in payload['tolerances']:
        row = {'tolerance': tolerance, 'methods': {}}
        for method in ['refined-swift-verified', 'hybrid-swift']:
            calls = [c for c in candidates if c['tolerance'] == tolerance and c['method'] == method]
            times = sorted(statistics.median(c['timesMs']) for c in calls)
            row['methods'][method] = {'attempts': len(times), 'medianMs': statistics.median(times),
                'sumMedianMs': sum(times), 'p95Ms': times[int(.95 * (len(times) - 1))]}
        rows.append(row)
    output = {'geometryAndFitterChoicesUnchanged': True, 'repeats': payload['repeats'], 'warmups': 2,
        'processSeconds': time.monotonic() - started, 'driverSHA256': digest(driver), 'rows': rows,
        'scope': 'Same multi-span jobs and full Swift pipeline workload. Run after other local checks; does not measure end-to-end matching.'}
    (report / 'isolated-timing.json').write_text(json.dumps(output, indent=2, sort_keys=True) + '\n')
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
