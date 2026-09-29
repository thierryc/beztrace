#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Build a local universal engine; never signs, installs or publishes."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.1.1-dev.3'


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'.build'/('beztrace-'+VERSION))
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('Output already exists; choose a fresh directory to preserve rollback')
    slices = []
    for arch in ('arm64', 'x86_64'):
        scratch = ROOT/'.build'/('dev-engine-'+arch)
        subprocess.run(['swift', 'build', '-c', 'release', '--product', 'beztrace',
                        '--triple', arch+'-apple-macosx13.0', '--scratch-path', str(scratch)],
                       cwd=ROOT, check=True)
        binary = scratch/(arch+'-apple-macosx')/'release/beztrace'
        if not binary.is_file():
            raise RuntimeError('Missing compiled slice: '+str(binary))
        slices.append(binary)
    (output/'bin').mkdir(parents=True)
    binary = output/'bin/beztrace'
    subprocess.run(['lipo', '-create', *map(str, slices), '-output', str(binary)], check=True)
    assert set(run('lipo', '-archs', str(binary)).split()) == {'arm64', 'x86_64'}
    assert run(str(binary), '--version') == 'beztrace '+VERSION
    for source in ('LICENSE-APACHE', 'LICENSE-MIT', 'THIRD_PARTY_NOTICES', 'Schemas/trace-result-v1.schema.json'):
        shutil.copy2(ROOT/source, output/Path(source).name)
    subprocess.run(['python3', str(ROOT/'scripts/generate_sbom.py'), '--binary', str(binary),
                    '--output-dir', str(output), '--release-kind', 'development', '--version', VERSION], check=True)
    inventory = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted(output.rglob('*')) if p.is_file()}
    sources = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted((ROOT/'Sources').rglob('*.swift'))}
    receipt = dict(version=VERSION, architectures=['arm64','x86_64'], minimumMacOS='13.0',
                   schemaVersion=1, pathDataVersion=2, sourceRevision=run('git','rev-parse','HEAD'),
                   sourceTreeDirty=bool(run('git','status','--porcelain','--untracked-files=normal')),
                   developerIDSigning='not-performed', notarization='not-submitted',
                   swiftToolchain=run('swift','--version'), sourceFiles=sources, files=inventory)
    (output/'development-engine.json').write_text(json.dumps(receipt,indent=2)+'\n')
    inventory['development-engine.json'] = hashlib.sha256((output/'development-engine.json').read_bytes()).hexdigest()
    (output/'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name,digest in sorted(inventory.items())))
    print(json.dumps(dict(executable=str(binary),version=VERSION,sha256=inventory['bin/beztrace']),indent=2))


if __name__ == '__main__':
    main()
