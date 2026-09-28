#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Read-only verification of a built companion's manifest, ZIP, and payload."""
import argparse
import hashlib
import json
from pathlib import Path,PurePosixPath
import stat
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'))
from beztrace_companion.contract import validate_schema


def verify(directory):
    manifest=json.loads((directory/'companion-manifest.json').read_text())
    validate_schema(manifest,json.loads((ROOT/'manifest-v1.schema.json').read_text()))
    inventory=manifest['payload']
    if not (inventory==sorted(inventory,key=lambda item:item['path'])):
        raise ValueError('Inventory must be sorted')
    if not (hashlib.sha256(json.dumps(inventory,sort_keys=True,separators=(',',':')).encode()).hexdigest()==manifest['payloadSha256']):
        raise ValueError('Package validation failed at verify_package.py:23')
    expected={entry['path']:entry for entry in inventory}
    if not (len(expected)==len(inventory)):
        raise ValueError('Duplicate inventory path')
    for name in expected:
        path=PurePosixPath(name)
        if not (not path.is_absolute() and '..' not in path.parts and str(path)==name):
            raise ValueError('Unsafe payload path')
    if not (len(manifest['artifacts'])==1):
        raise ValueError('Package validation failed at verify_package.py:29')
    artifact=manifest['artifacts'][0]
    if not (PurePosixPath(artifact['path']).name==artifact['path']):
        raise ValueError('Unsafe artifact path')
    archive=directory/artifact['path']
    if not (archive.stat().st_size==artifact['size']):
        raise ValueError('Package validation failed at verify_package.py:33')
    if not (hashlib.sha256(archive.read_bytes()).hexdigest()==artifact['sha256']):
        raise ValueError('Package validation failed at verify_package.py:34')
    with zipfile.ZipFile(archive) as z:
        seen=set()
        for member in z.infolist():
            path=PurePosixPath(member.filename)
            if not (not path.is_absolute() and '..' not in path.parts):
                raise ValueError('Package validation failed at verify_package.py:39')
            if not (path.parts[0]==manifest['bundleName']):
                raise ValueError('Package validation failed at verify_package.py:40')
            relative='/'.join(path.parts[1:])
            if not (relative not in seen and relative in expected):
                raise ValueError('Unexpected or duplicate ZIP entry')
            seen.add(relative)
            mode=member.external_attr>>16
            if not (stat.S_ISREG(mode)):
                raise ValueError('ZIP must contain only regular files')
            entry=expected[relative]
            if not (member.file_size==entry['size'] and member.file_size<64*1024*1024):
                raise ValueError('Package validation failed at verify_package.py:47')
            if not (bool(mode&stat.S_IXUSR)==entry['executable']):
                raise ValueError('Package validation failed at verify_package.py:48')
            if not (hashlib.sha256(z.read(member)).hexdigest()==entry['sha256']):
                raise ValueError('Payload checksum mismatch')
        if not (seen==set(expected)):
            raise ValueError('Missing ZIP entries')
    # The unpacked bundle is also a delivered artifact, so verify its bytes.
    bundle=directory/manifest['bundleName']
    actual={p.relative_to(bundle).as_posix() for p in bundle.rglob('*') if p.is_file()}
    if not (actual==set(expected)):
        raise ValueError('Unpacked bundle inventory differs')
    for name,entry in expected.items():
        path=bundle/name
        if not (not path.is_symlink()):
            raise ValueError('Package validation failed at verify_package.py:57')
        if not (hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']):
            raise ValueError('Package validation failed at verify_package.py:58')
        if not (bool(path.stat().st_mode&stat.S_IXUSR)==entry['executable']):
            raise ValueError('Package validation failed at verify_package.py:59')
    for line in (directory/'SHA256SUMS').read_text().splitlines():
        digest,name=line.split('  ',1)
        if not (name in [artifact['path'],'companion-manifest.json']):
            raise ValueError('Package validation failed at verify_package.py:62')
        if not (hashlib.sha256((directory/name).read_bytes()).hexdigest()==digest):
            raise ValueError('Package validation failed at verify_package.py:63')
    return manifest


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    args=parser.parse_args()
    result=verify(args.directory)
    print('Verified manifest, archive, payload, and checksums; native qualification: '+result['qualification']['status'])
