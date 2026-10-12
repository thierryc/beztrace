#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Replay an explicitly supplied private raster handoff without changing it."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import math


def digest(data):
    return hashlib.sha256(data).hexdigest()


def identical_outline(a, b):
    if len(a['contours']) != len(b['contours']): return False
    for p, q in zip(a['contours'], b['contours']):
        if p['closed'] != q['closed'] or len(p['nodes']) != len(q['nodes']): return False
        for x, y in zip(p['nodes'], q['nodes']):
            if x['type'] != y['type'] or x['smooth'] != y['smooth']: return False
            if any(struct.pack('>d', x[k]) != struct.pack('>d', y[k]) for k in ('x', 'y')): return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--handoff', required=True, type=Path)
    parser.add_argument('--engine', required=True, type=Path)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--control-comparison', choices=['byte-identical', 'geometry'], default='byte-identical',
                        help='Geometry mode records numeric changes after a math correction; fixed reference, types, flags, counts and the original source-tolerance gate remain mandatory')
    args = parser.parse_args()
    root = args.handoff.resolve(); output = args.output.resolve()
    if output.exists(): parser.error('Output already exists; choose a fresh evidence directory')
    manifest = json.loads((root/'manifest.json').read_text())
    for item in manifest['files']:
        data = (root/item['path']).read_bytes()
        assert len(data) == item['bytes'] and digest(data) == item['sha256'], item['path']
    cases = json.loads((root/'cases.json').read_text())
    cases += [dict(case='passing-r-control', request='fixtures/passing-r-control.json')]
    output.mkdir(parents=True)
    receipt = dict(inputManifestSHA256=digest((root/'manifest.json').read_bytes()), engines={}, cases=[])
    results = {}
    for role, engine in [('baseline', args.baseline.resolve()), ('candidate', args.engine.resolve())]:
        info = dict(path=str(engine), sha256=digest(engine.read_bytes()))
        for arguments in (['--version'], ['capabilities', '--format', 'json']):
            p = subprocess.run([str(engine), *arguments], capture_output=True, timeout=10)
            assert p.returncode == 0 and not p.stderr
            info[' '.join(arguments)] = p.stdout.decode()
        receipt['engines'][role] = info
        folder = output/role; folder.mkdir()
        for case in cases:
            name = case['case']; request_path = root/case['request']; request_data = request_path.read_bytes()
            p = subprocess.run([str(engine), 'match', str(request_path), '--json-errors'], capture_output=True, timeout=30)
            (folder/(name+'.stdout')).write_bytes(p.stdout)
            (folder/(name+'.stderr')).write_bytes(p.stderr)
            (folder/(name+'.exit')).write_text(str(p.returncode)+'\n')
            item = dict(engine=role, case=name, exit=p.returncode, requestSHA256=digest(request_data),
                        stdoutSHA256=digest(p.stdout), stderrSHA256=digest(p.stderr))
            if role == 'baseline':
                if 'expectedError' in case:
                    assert p.returncode == 5 and not p.stdout
                    assert p.stderr == (root/case['expectedError']).read_bytes()
                else: assert p.returncode == 0 and not p.stderr
            else:
                assert p.returncode == 0 and not p.stderr, p.stderr.decode()
                request = json.loads(request_data); result = json.loads(p.stdout)
                assert identical_outline(request['reference']['outline'], result['reference']['outline'])
                nodes = [n for c in result['target']['outline']['contours'] for n in c['nodes']]
                assert len(nodes) == request['options']['maxNodes']
                assert sum(n['type'] != 'offcurve' for n in nodes) == request['options']['maxOnCurveNodes']
                assert [[n['type'] for n in c['nodes']] for c in result['target']['outline']['contours']] == [
                    [n['type'] for n in c['nodes']] for c in request['reference']['outline']['contours']]
                source = result['rasterSources'][0]
                assert source['sha256'] == digest(base64.b64decode(request['images'][0]['imageData']))
                assert source['transform'] == request['images'][0]['transform']
                assert source['maximumBoundaryDeviation'] <= request['options']['fitTolerance']
                item.update(maximumBoundaryDeviation=source['maximumBoundaryDeviation'], referenceBitwiseUnchanged=True,
                            onCurves=sum(n['type'] != 'offcurve' for n in nodes), totalNodes=len(nodes))
                (output/(name+'.master-set.json')).write_bytes(p.stdout)
            results[role, name] = p.stdout
            receipt['cases'].append(item)
    receipt['passingControlByteIdentical'] = results['baseline', 'passing-r-control'] == results['candidate', 'passing-r-control']
    baseline_control=json.loads(results['baseline','passing-r-control'])
    candidate_control=json.loads(results['candidate','passing-r-control'])
    assert identical_outline(baseline_control['reference']['outline'],candidate_control['reference']['outline'])
    first=baseline_control['target']['outline']['contours'];second=candidate_control['target']['outline']['contours']
    assert len(first)==len(second)
    maximum=0.0
    for a,b in zip(first,second):
        assert a['closed']==b['closed'] and len(a['nodes'])==len(b['nodes'])
        for x,y in zip(a['nodes'],b['nodes']):
            assert x['type']==y['type'] and x['smooth']==y['smooth']
            maximum=max(maximum,math.hypot(x['x']-y['x'],x['y']-y['y']))
    receipt['controlComparison']=dict(mode=args.control_comparison,maximumNodeDisplacement=maximum,
        referenceBitwiseUnchanged=True,structureAndFlagsUnchanged=True,
        explanation='Numeric changes are recorded, never rounded away. Candidate source deviation must still pass the original request tolerance.')
    if args.control_comparison=='byte-identical':assert receipt['passingControlByteIdentical']
    else:
        control_request=json.loads((root/'fixtures/passing-r-control.json').read_bytes())
        assert maximum<=control_request['options']['fitTolerance']
    (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps(dict(output=str(output), cases=len(cases),passingControlByteIdentical=receipt['passingControlByteIdentical'],maximumControlNodeDisplacement=maximum)))


if __name__ == '__main__': main()
