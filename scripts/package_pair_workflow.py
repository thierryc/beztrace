#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Stage an unsigned local pair-workflow archive. Never install or publish."""
import argparse,hashlib,json,pathlib,shutil,subprocess,zipfile

def main():
    p=argparse.ArgumentParser();p.add_argument('--architecture-evidence',type=pathlib.Path);p.add_argument('--arm64',required=True,type=pathlib.Path);p.add_argument('--x86-64',required=True,type=pathlib.Path);p.add_argument('--evidence',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--verification-file',action='append',default=[],type=pathlib.Path);a=p.parse_args()
    root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);(out/'bin').mkdir()
    binary=out/'bin/beztrace';subprocess.run(['lipo','-create',str(a.arm64.resolve()),str(a.x86_64.resolve()),'-output',str(binary)],check=True);binary.chmod(0o755)
    caps=json.loads(subprocess.check_output([str(binary),'capabilities','--format','json']));assert caps['pairJobVersion']==1
    shutil.copytree(root/'Schemas',out/'schemas')
    for n in ['LICENSE-APACHE','LICENSE-MIT','THIRD_PARTY_NOTICES']:
        if (root/n).exists():shutil.copy2(root/n,out/n)
    shutil.copy2(root/'docs/PAIR_WORKFLOW.md',out/'WORKFLOW.md')
    shutil.copytree(a.evidence/'examples',out/'examples');shutil.copytree(a.evidence/'results',out/'review/results');shutil.copy2(a.evidence/'index.html',out/'review/index.html');shutil.copy2(a.evidence/'receipt.json',out/'review/receipt.json')
    (out/'run-example.sh').write_text('''#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
example=${1:-Y-images-smart}
result=${2:-"$PWD/beztrace-pair-result"}
exec "$package_dir/bin/beztrace" match-pair "$package_dir/examples/$example.job.json" --output-directory "$result" --json-errors
''');(out/'run-example.sh').chmod(0o755)
    architecture=None
    if a.architecture_evidence:
        architecture=json.loads(a.architecture_evidence.read_text())
        assert architecture['arm64EngineSHA256']==hashlib.sha256(a.arm64.read_bytes()).hexdigest()
        assert architecture['x86_64EngineSHA256']==hashlib.sha256(a.x86_64.read_bytes()).hexdigest()
        assert len(architecture['cases'])>=18
    architecture_status=('Recorded pair artifacts are byte-identical on arm64 and x86_64/Rosetta.' if architecture and architecture['byteIdentical'] else 'Cross-architecture qualification is pending or failed.')
    (out/'README.txt').write_text(f'''BezTrace pair workflow — unsigned LOCAL development candidate

Run from Terminal without installing:
  ./run-example.sh Y-images-smart /tmp/beztrace-Y-images
  ./run-example.sh R-mixed-direct /tmp/beztrace-R-mixed
  ./run-example.sh R-outlines-smart /tmp/beztrace-R-outlines

Choose a new output directory for each run. Open its index.html to review
paired paths, five interpolation positions and numbered endpoint nodes.
See WORKFLOW.md and examples/ for the job format and explicit limits.

The universal executable contains arm64 and x86_64 slices. No Developer ID
signing or notarization was performed. It is not a qualified release.
{architecture_status} Nothing installs,
launches Glyphs, applies font data or publishes files. Python is not required.
''')
    identity={'kind':'unsigned-local-development','engineSHA256':hashlib.sha256(binary.read_bytes()).hexdigest(),'slices':{'arm64':hashlib.sha256(a.arm64.read_bytes()).hexdigest(),'x86_64':hashlib.sha256(a.x86_64.read_bytes()).hexdigest()},'architectures':subprocess.check_output(['lipo','-archs',str(binary)]).decode().strip(),'version':subprocess.check_output([str(binary),'--version']).decode().strip(),'capabilities':caps,'runtimeLibraries':subprocess.check_output(['otool','-L',str(binary)]).decode(),'releaseQualified':False,'nativeApplied':False,'crossArchitectureEvidence':architecture,'qualificationBlockers':([] if architecture and architecture['byteIdentical'] else ['Cross-architecture qualification pending or failed.'])+['Native Intel release execution, Developer ID signing, notarization and distribution gates not performed.']}
    (out/'build-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
    if a.verification_file:
        (out/'verification').mkdir()
        for f in a.verification_file:shutil.copy2(f,out/'verification'/f.name)
    hashes={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(out.rglob('*')) if f.is_file()};(out/'SHA256SUMS').write_text(''.join(f'{h}  {name}\n' for name,h in hashes.items()))
    archive=out.parent/(out.name+'.zip')
    if archive.exists():raise FileExistsError(archive)
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for f in sorted(out.rglob('*')):
            if f.is_file():z.write(f,str(pathlib.Path(out.name)/f.relative_to(out)))
    print(archive)
if __name__=='__main__':main()
