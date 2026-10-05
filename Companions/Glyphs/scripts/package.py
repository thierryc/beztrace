#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Reproduce an unsigned companion payload and content-addressed installer manifest.

Never signs, installs, downloads, publishes, or launches Glyphs.
"""
import argparse
import ast
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
BUNDLE = ROOT/'Beztrace.glyphsPlugin'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,value): path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')


def inventory(bundle):
    return [dict(path=p.relative_to(bundle).as_posix(),sha256=sha(p),size=p.stat().st_size,
                 executable=bool(p.stat().st_mode & stat.S_IXUSR))
            for p in sorted(bundle.rglob('*')) if p.is_file()]


def validate_source():
    meta=plistlib.loads((BUNDLE/'Contents/Info.plist').read_bytes())
    if not (meta['CFBundleIdentifier']=='dev.beztrace.glyphs'):
        raise ValueError('Package validation failed at package.py:38')
    if not (meta['CFBundleShortVersionString']=='0.1.0' and meta['CFBundleVersion']=='13'):
        raise ValueError('Package validation failed at package.py:39')
    source=json.loads((BUNDLE/'Contents/Resources/GlyphsSDK-SOURCE.json').read_text())
    loader=BUNDLE/'Contents/MacOS/plugin'
    if not (sha(loader)==source['loaderSha256']):
        raise ValueError('SDK loader checksum mismatch')
    if not (set(subprocess.check_output(['lipo','-archs',str(loader)],text=True).split())=={'arm64','x86_64'}):
        raise ValueError('Package validation failed at package.py:43')
    if not (os.access(loader,os.X_OK)):
        raise ValueError('Package validation failed at package.py:44')
    for p in BUNDLE.rglob('*.py'):
        ast.parse(p.read_text(),filename=str(p))
    if not ((BUNDLE/'Contents/Resources/trace-result-v1.schema.json').read_bytes()==(REPO/'Schemas/trace-result-v1.schema.json').read_bytes()):
        raise ValueError('Package validation failed at package.py:47')
    return meta,source


def build(output):
    meta,source=validate_source()
    output=output.resolve()
    # Fresh staging only. Never delete an existing artifact or a live installation.
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be a new or empty directory')
    support=(Path.home()/'Library/Application Support').resolve()
    if output==support or support in output.parents or output==BUNDLE or BUNDLE in output.parents:
        raise ValueError('Refusing to package into Application Support or source bundle')
    output.mkdir(parents=True,exist_ok=True)
    bundle=output/BUNDLE.name
    shutil.copytree(BUNDLE,bundle,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
    resources=bundle/'Contents/Resources'
    for name in ['LICENSE-APACHE','LICENSE-MIT','THIRD_PARTY_NOTICES']:
        shutil.copy2(REPO/name,resources/name)
    for document in sorted(ROOT.glob('*.md')):
        shutil.copy2(document,resources/document.name)
    shutil.copy2(ROOT/'manifest-v1.schema.json',resources/'companion-manifest-v1.schema.json')
    files=inventory(bundle)
    fingerprint=hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    dirty=bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],cwd=REPO,text=True).strip())
    sbom={
        'spdxVersion':'SPDX-2.3','dataLicense':'CC0-1.0','SPDXID':'SPDXRef-DOCUMENT',
        'name':'Beztrace for Glyphs 0.1.0',
        'documentNamespace':'https://beztrace.dev/spdx/glyphs/0.1.0/'+fingerprint,
        'creationInfo':{'created':'2026-09-27T00:00:00Z','creators':['Organization: beztrace contributors']},
        'packages':[
            {'name':'Beztrace for Glyphs','SPDXID':'SPDXRef-Companion','versionInfo':'0.1.0',
             'downloadLocation':'NOASSERTION','filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT',
             'licenseDeclared':'Apache-2.0 OR MIT','copyrightText':'Copyright 2026 beztrace contributors'},
            {'name':'GlyphsSDK general plugin loader','SPDXID':'SPDXRef-GlyphsSDK','versionInfo':source['revision'],
             'downloadLocation':source['source'],'filesAnalyzed':False,'licenseConcluded':'Apache-2.0',
             'licenseDeclared':'Apache-2.0','copyrightText':'NOASSERTION',
             'checksums':[{'algorithm':'SHA256','checksumValue':source['loaderSha256']}]},
            {'name':'beztrace CLI (external prerequisite)','SPDXID':'SPDXRef-Engine','versionInfo':'0.1.0',
             'downloadLocation':'https://github.com/thierryc/beztrace/releases/tag/v0.1.0',
             'filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT','licenseDeclared':'Apache-2.0 OR MIT',
             'copyrightText':'Copyright 2026 beztrace contributors and img2bez Authors'},
            {'name':'beztrace CLI (supported development prerequisite)',
             'SPDXID':'SPDXRef-DevelopmentEngine1','versionInfo':'0.1.1-dev.1','downloadLocation':'NOASSERTION',
             'filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT','licenseDeclared':'Apache-2.0 OR MIT',
             'copyrightText':'Copyright 2026 beztrace contributors and img2bez Authors'},
            {'name':'beztrace CLI (supported development prerequisite)',
             'SPDXID':'SPDXRef-DevelopmentEngine2','versionInfo':'0.1.1-dev.2','downloadLocation':'NOASSERTION',
             'filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT','licenseDeclared':'Apache-2.0 OR MIT',
             'copyrightText':'Copyright 2026 beztrace contributors and img2bez Authors'},
            {'name':'beztrace CLI (supported development prerequisite)',
             'SPDXID':'SPDXRef-DevelopmentEngine3','versionInfo':'0.1.1-dev.3','downloadLocation':'NOASSERTION',
             'filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT','licenseDeclared':'Apache-2.0 OR MIT',
             'copyrightText':'Copyright 2026 beztrace contributors and img2bez Authors'},
            {'name':'beztrace CLI (preferred local development prerequisite)',
             'SPDXID':'SPDXRef-DevelopmentEngine4','versionInfo':'0.1.1-dev.4','downloadLocation':'NOASSERTION',
             'filesAnalyzed':False,'licenseConcluded':'Apache-2.0 OR MIT','licenseDeclared':'Apache-2.0 OR MIT',
             'copyrightText':'Copyright 2026 beztrace contributors and img2bez Authors'}],
        'relationships':[
            {'spdxElementId':'SPDXRef-DOCUMENT','relationshipType':'DESCRIBES','relatedSpdxElement':'SPDXRef-Companion'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'CONTAINS','relatedSpdxElement':'SPDXRef-GlyphsSDK'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON','relatedSpdxElement':'SPDXRef-Engine',
             'comment':'Alternative to the local development engine; only one executable is selected at runtime.'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON','relatedSpdxElement':'SPDXRef-DevelopmentEngine1',
             'comment':'Supported alternative to released 0.1.0, not bundled with the companion.'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON','relatedSpdxElement':'SPDXRef-DevelopmentEngine2',
             'comment':'Supported alternative to released 0.1.0, not bundled with the companion.'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON','relatedSpdxElement':'SPDXRef-DevelopmentEngine3',
             'comment':'Supported alternative to released 0.1.0, not bundled with the companion.'},
            {'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON','relatedSpdxElement':'SPDXRef-DevelopmentEngine4',
             'comment':'Preferred local alternative to released 0.1.0, not bundled with the companion.'}]}
    sbom['packages'].append(dict(sbom['packages'][2], SPDXID='SPDXRef-StableEngine1',
                                 versionInfo='0.1.1', downloadLocation='https://github.com/thierryc/beztrace/releases/tag/v0.1.1'))
    sbom['relationships'].append({'spdxElementId':'SPDXRef-Companion','relationshipType':'DEPENDS_ON',
                                 'relatedSpdxElement':'SPDXRef-StableEngine1',
                                 'comment':'Supported stable alternative; never bundled.'})
    write_json(resources/'sbom.spdx.json',sbom)
    archive=output/'beztrace-glyphs-0.1.0-build13-macos-universal.zip'
    # Glyphs caches timestamp-based Python bytecode outside the bundle. Each
    # independently numbered build must invalidate same-size source changes,
    # while repeat packages of that build remain byte-reproducible. ZIP times
    # have two-second resolution; reserve one distinct slot per build.
    stamp = (datetime(2026, 9, 27) + timedelta(seconds=2*int(meta['CFBundleVersion']))).timetuple()[:6]
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(bundle.rglob('*')):
            if not p.is_file(): continue
            info=zipfile.ZipInfo(p.relative_to(output).as_posix(),stamp)
            info.create_system=3
            mode=0o755 if os.access(p,os.X_OK) else 0o644
            info.external_attr=(stat.S_IFREG|mode)<<16
            info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,p.read_bytes(),compresslevel=9)
    files=inventory(bundle)
    manifest={
        'schemaVersion':1,'id':'beztrace-glyphs','name':'Beztrace for Glyphs','version':'0.1.0','build':13,
        'bundleIdentifier':'dev.beztrace.glyphs','bundleName':'Beztrace.glyphsPlugin',
        'sourceRevision':revision,'sourceTreeDirty':dirty,'payloadSha256':hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
        'platform':{'minimumMacOS':'13.0','architectures':['arm64','x86_64'],
                    'glyphsBundleIdentifier':'com.GeorgSeifert.Glyphs4','glyphsMajorVersion':4,'minimumGlyphsBuild':4107,
                    'python':{'minimumVersion':'3.9','provider':'Glyphs Python runtime','modules':['GlyphsApp','objc','AppKit','Foundation','Quartz']}},
        'engine':{'name':'beztrace','versions':['0.1.0','0.1.1-dev.1','0.1.1-dev.2','0.1.1-dev.3','0.1.1-dev.4','0.1.1'],'bundled':False,'schemaVersions':[1],'pathDataVersions':[2],
                  'defaultExecutable':'/Library/Application Support/beztrace/bin/beztrace',
                  'releaseUrl':'https://github.com/thierryc/beztrace/releases/tag/v0.1.0'},
        'installation':{'root':'glyphs4ApplicationSupport','relativePath':'Plugins/Beztrace.glyphsPlugin',
                        'requiresRelaunch':True,'sharedEngineRemoval':False},
        'qualification':{'nativeTestedBuilds':[],'status':'development-unqualified'},
        'artifacts':[{'path':archive.name,'sha256':sha(archive),'size':archive.stat().st_size,'format':'zip',
                      'signing':{'status':'unsigned','teamIdentifier':None},'notarization':{'status':'not-submitted'}}],
        'payload':files,'sbom':'Beztrace.glyphsPlugin/Contents/Resources/sbom.spdx.json'}
    sys.path.insert(0,str(BUNDLE/'Contents/Resources'))
    from beztrace_companion.contract import validate_schema
    validate_schema(manifest,json.loads((ROOT/'manifest-v1.schema.json').read_text()))
    write_json(output/'companion-manifest.json',manifest)
    (output/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in [archive,output/'companion-manifest.json']))
    return manifest


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    try:
        manifest=build(args.output)
        print(json.dumps({'output':str(args.output.resolve()),'artifact':manifest['artifacts'][0],
                          'nativeQualification':manifest['qualification']},indent=2))
    except (ValueError,AssertionError,OSError,subprocess.CalledProcessError) as exc:
        parser.exit(1,str(exc)+'\n')
