#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Compare complete detached pair artifacts, without rounding or exclusions."""
import argparse
import json
from pathlib import Path


def compare(first: Path, second: Path):
    receipts = [json.loads((p / 'receipt.json').read_text()) for p in [first, second]]
    names = [[c['case'] for c in r['cases']] for r in receipts]
    if names[0] != names[1] or len(set(names[0])) != len(names[0]):
        raise ValueError('Both receipts must contain the same unique ordered cases')
    cases = []
    for name in names[0]:
        directories = [p / 'results' / name for p in [first, second]]
        files = [sorted(f.name for f in p.iterdir() if f.is_file()) for p in directories]
        differences = sorted(set(files[0]) ^ set(files[1]))
        for file in sorted(set(files[0]) & set(files[1])):
            if (directories[0] / file).read_bytes() != (directories[1] / file).read_bytes():
                differences.append(file)
        reports = [json.loads((p / 'comparison.json').read_text()) for p in directories]
        # Provenance disagreement is a comparison setup failure, not determinism.
        for key in ['sourceHashes', 'inputFiles', 'options', 'strategy']:
            if reports[0][key] != reports[1][key]:
                raise ValueError(f'{name}: unequal comparison inputs: {key}')
        cases.append({'case': name, 'byteIdentical': not differences,
                      'differentFiles': differences,
                      'artifactCount': len(files[0])})
    return {'arm64EngineSHA256': receipts[0]['engineSHA256'],
            'x86_64EngineSHA256': receipts[1]['engineSHA256'],
            'cases': cases, 'byteIdentical': all(c['byteIdentical'] for c in cases),
            'releaseQualified': False,
            'scope': 'Every emitted file for the recorded pair matrix; no float rounding. Intel execution under Rosetta does not replace native Intel release qualification.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arm64', required=True, type=Path)
    parser.add_argument('--x86-64', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = compare(args.arm64, args.x86_64)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(f"{sum(c['byteIdentical'] for c in result['cases'])}/{len(result['cases'])} cases byte-identical")
    return 0 if result['byteIdentical'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
