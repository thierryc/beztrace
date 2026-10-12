#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Replay immutable owned R/Y controls through the file-based pair CLI.
This is development evidence, not release or native-font qualification.
"""
import argparse,hashlib,json,pathlib,shutil,subprocess,time

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--engine',required=True,type=pathlib.Path);parser.add_argument('--output',required=True,type=pathlib.Path)
    args=parser.parse_args();engine=args.engine.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    root=pathlib.Path(__file__).resolve().parents[1];source=root/'Tests/Fixtures/matching/pair-v1';assets=out/'examples/assets';assets.mkdir(parents=True)
    manifest=json.loads((source/'manifest.json').read_text())
    for name,expected in manifest['files'].items():
        assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected,name
        shutil.copy2(source/name,assets/name)
    schemas=root/'Schemas'
    import jsonschema
    store={}
    for p in schemas.glob('*.json'):
        schema=json.loads(p.read_text())
        for key in [schema.get('$id',p.as_uri()),p.as_uri(),'https://beztrace.dev/schema/'+p.name]:store[key]=schema
    def validate(value,name):
        schema=json.loads((schemas/name).read_text());resolver=jsonschema.RefResolver(base_uri=schemas.as_uri()+'/',referrer=schema,store=store)
        jsonschema.Draft202012Validator(schema,resolver=resolver).validate(value)
    records=[]
    for glyph in ['R','Y']:
        regular=json.loads((source/(glyph+'-regular.outline.json')).read_text());on=sum(n['type']!='offcurve' for c in regular['contours'] for n in c['nodes']);total=sum(len(c['nodes']) for c in regular['contours'])
        for scenario in ['outlines','mixed','images']:
            for strategy in ['direct','smart','retrace-target','retrace-both']:
                if scenario!='outlines' and strategy=='retrace-target' or scenario=='images' and strategy=='retrace-both':continue
                unlocked=strategy=='retrace-both'
                inputs=[]
                for weight in ['regular','bold']:
                    kind='image' if scenario=='images' or scenario=='mixed' and weight=='bold' else 'outline'
                    entry={'id':weight,'kind':kind,'path':'assets/'+glyph+'-'+weight+('.png' if kind=='image' else '.outline.json')}
                    if kind=='image':entry['transform']=json.loads((source/(glyph+'-'+weight+'.transform.json')).read_text())
                    inputs.append(entry)
                job={'schemaVersion':1,'unitsPerEm':1000,'axis':{'tag':'wght','locations':[400,700]},'inputs':inputs,'strategy':strategy}
                if scenario=='images' or unlocked:job['options']={'referencePolicy':'shared-subdivision','maxAdditionalOnCurveNodes':40,'maxOnCurveNodes':64,'maxNodes':160}
                stem=glyph+'-'+scenario+'-'+strategy;file=out/'examples'/(stem+'.job.json');file.write_text(json.dumps(job,indent=2)+'\n');validate(job,'pair-job-v1.schema.json')
                started=time.monotonic();result=out/'results'/stem
                process=subprocess.run([str(engine),'match-pair',str(file),'--output-directory',str(result),'--json-errors'],capture_output=True,timeout=120)
                result.parent.mkdir(exist_ok=True)
                (result.parent/(stem+'.stdout')).write_bytes(process.stdout);(result.parent/(stem+'.stderr')).write_bytes(process.stderr)
                report=json.loads((result/'comparison.json').read_text());validate(report,'pair-comparison-v1.schema.json')
                for p in result.glob('*.master-set.json'):validate(json.loads(p.read_text()),'master-set-v1.schema.json')
                if report.get('recommendedRoute'):
                    pair=json.loads((result/'recommended.master-set.json').read_text())
                    if scenario!='images' and not unlocked:assert pair['reference']['outline']==regular
                    assert all(v['upperBound']<=1 for c in report['candidates'] if c['accepted'] for v in c['sourceDeviations'])
                assert process.returncode==(0 if report.get('recommendedRoute') else 5)
                records.append({'case':stem,'exitCode':process.returncode,'seconds':time.monotonic()-started,'recommendedRoute':report.get('recommendedRoute'),'candidates':report['candidates'],'reportSHA256':hashlib.sha256((result/'comparison.json').read_bytes()).hexdigest()})
                print(stem,process.returncode,report.get('recommendedRoute'),flush=True)
    identity={'enginePath':str(engine),'engineSHA256':hashlib.sha256(engine.read_bytes()).hexdigest(),'engineVersion':subprocess.check_output([str(engine),'--version']).decode().strip(),'capabilities':json.loads(subprocess.check_output([str(engine),'capabilities','--format','json'])),'cases':records,'qualification':'detached development; native and release gates not established'}
    (out/'receipt.json').write_text(json.dumps(identity,indent=2)+'\n')
    rows=''.join(f'<tr><td>{r["case"]}</td><td>{r["exitCode"]}</td><td>{r["recommendedRoute"] or "refused"}</td><td><a href="results/{r["case"]}/index.html">review</a></td></tr>' for r in records)
    (out/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>BezTrace pair qualification</title><style>body{font:16px/1.5 system-ui;max-width:1200px;margin:auto;padding:30px}td,th{padding:10px;border-bottom:1px solid #ddd}table{border-collapse:collapse}</style><h1>R/Y pair workflow evidence</h1><p>Owned known-outline controls. All sources frozen before fitting. Refusals remain visible; no native font application.</p><table><tr><th>Case</th><th>Exit</th><th>Recommendation</th><th>Evidence</th></tr>'+rows+'</table>')

if __name__=='__main__':main()
