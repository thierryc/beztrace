#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Offline, maintenance-only curve fitting/selection experiment. See README.md."""
from __future__ import annotations
import argparse
import hashlib
import html
import json
import math
import platform
import statistics
import subprocess
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
METHODS = ('least-squares-8', 'least-squares-refined', 'levien-kurbo-0.13.1', 'hybrid', 'refined-swift-verified', 'hybrid-swift')
REPORT_METHODS = METHODS + ('hybrid-swift-smoothed',)


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')


def command(args, *, payload=None, timeout=600):
    r = subprocess.run([str(a) for a in args], input=None if payload is None else json.dumps(payload),
                       text=True, capture_output=True, timeout=timeout, cwd=ROOT)
    if r.returncode:
        raise RuntimeError(f'{args}: exit {r.returncode}\n{r.stderr[-5000:]}')
    return r.stdout


def lerp(a, b, t):
    return [x + (y-x)*t for x, y in zip(a,b)]


def split(c, t=.5):
    p = [c[i:i+2] for i in range(0,8,2)]
    a,b,d = [lerp(p[i],p[i+1],t) for i in range(3)]
    e,f = lerp(a,b,t),lerp(b,d,t)
    q = lerp(e,f,t)
    return p[0]+a+e+q, q+f+d+p[3]


def spans(outline):
    result=[]
    for contour in outline['contours']:
        n=contour['nodes']; first=next(i for i,p in enumerate(n) if p['type']!='offcurve')
        i=first; segments=[]
        while True:
            j=(i+1)%len(n); p=[n[i]['x'],n[i]['y']]
            line=n[j]['type']!='offcurve'
            if line:
                end=[n[j]['x'],n[j]['y']]; c=p+lerp(p,end,1/3)+lerp(p,end,2/3)+end
            else:
                k=(j+1)%len(n);j=(j+2)%len(n)
                c=p+[n[(i+1)%len(n)]['x'],n[(i+1)%len(n)]['y'],n[k]['x'],n[k]['y'],n[j]['x'],n[j]['y']]
            segments.append(dict(curve=c,line=line,smooth=bool(n[i].get('smooth',False))))
            i=j
            if i==first: break
        result.append(segments)
    return result


def outline(contours):
    cs=[]
    for segs in contours:
        nodes=[]
        for i,s in enumerate(segs):
            c=s['curve']
            nodes.append(dict(x=c[0],y=c[1],type='line' if segs[i-1]['line'] else 'curve',smooth=s['smooth']))
            if not s['line']:
                nodes.extend([dict(x=c[2],y=c[3],type='offcurve',smooth=False),dict(x=c[4],y=c[5],type='offcurve',smooth=False)])
        cs.append(dict(closed=True,nodes=nodes))
    return dict(contours=cs)


def sample(c, n=129):
    p=np.asarray(c,dtype=float).reshape(4,2)
    t=np.linspace(0,1,n)[:,None];u=1-t
    return u**3*p[0]+3*u*u*t*p[1]+3*u*t*t*p[2]+t**3*p[3]


def arc_samples(points, n=257):
    lengths=np.r_[0,np.cumsum(np.linalg.norm(np.diff(points,axis=0),axis=1))]
    if lengths[-1]<1e-12: return np.repeat(points[:1],n,axis=0)
    at=np.linspace(0,lengths[-1],n)
    return np.column_stack([np.interp(at,lengths,points[:,axis]) for axis in range(2)])


def turns(c):
    p=np.asarray(c).reshape(4,2);t=np.linspace(.001,.999,65)[:,None];u=1-t
    d=3*(u*u*(p[1]-p[0])+2*u*t*(p[2]-p[1])+t*t*(p[3]-p[2]))
    dd=6*(u*(p[2]-2*p[1]+p[0])+t*(p[3]-2*p[2]+p[1]))
    cross=d[:,0]*dd[:,1]-d[:,1]*dd[:,0]
    scale=max(float(np.max(np.abs(cross))),1)
    return [int(np.sign(x)) for x in cross if abs(x)>scale*1e-8]


def changes(values):
    return sum(a!=b for a,b in zip(values,values[1:]))


def quality(job, candidate):
    if candidate.get('curve') is None: return dict(orderedError=None,extraInflection=False)
    source=np.concatenate([sample(c)[:-1] for c in job['curves']]+[np.asarray(job['curves'][-1][-2:]).reshape(1,2)])
    target=sample(candidate['curve'],257)
    ordered=float(np.max(np.linalg.norm(arc_samples(source)-arc_samples(target),axis=1)))
    original=[x for c in job['curves'] for x in turns(c)]
    return dict(orderedError=ordered,extraInflection=changes(turns(candidate['curve']))>changes(original))


def protected(segments, i):
    a=segments[i-1];b=segments[i]
    if a['line'] or b['line']: return True
    ac=a['curve'];bc=b['curve']
    u=np.array(ac[-2:])-np.array(ac[4:6]);v=np.array(bc[2:4])-np.array(bc[:2])
    if np.linalg.norm(u)*np.linalg.norm(v)<1e-12: return True
    angle=math.atan2(abs(float(u[0]*v[1]-u[1]*v[0])),float(np.dot(u,v)))
    if angle>math.radians(1): return True
    # Preserve extrema already represented by an on-curve in either input.
    return abs(float(u[0]))<1e-7 or abs(float(u[1]))<1e-7


def ellipse(rx,ry,shear=0):
    k=.5522847498307936
    curves=[[rx,0,rx,k*ry,k*rx,ry,0,ry], [0,ry,-k*rx,ry,-rx,k*ry,-rx,0],
            [-rx,0,-rx,-k*ry,-k*rx,-ry,0,-ry],[0,-ry,k*rx,-ry,rx,-k*ry,rx,0]]
    return [dict(curve=[v for x,y in zip(c[::2],c[1::2]) for v in (x+shear*y+350,y+400)],line=False,smooth=True) for c in curves]


def refined_outline(directory, files):
    metadata=directory/'prepared-raster.json';files.append(metadata)
    meta=json.loads(metadata.read_text());scale=meta['options']['emHeight']/meta['height']*1000/1024
    contours=[]
    for path in sorted(directory.glob('raster-refined-*.json')):
        files.append(path);elements=json.loads(path.read_text())['path']['elements'];segs=[];at=None;start=None
        for e in elements:
            if e['type']=='move':at=start=[e['x']*scale,e['y']*scale]
            elif e['type']=='line':
                end=[e['x']*scale,e['y']*scale]
                segs.append(dict(curve=at+lerp(at,end,1/3)+lerp(at,end,2/3)+end,line=True,smooth=False));at=end
            elif e['type']=='curve':
                controls=[v*scale for p in e['points'] for v in p]
                segs.append(dict(curve=at+controls,line=False,smooth=False));at=controls[-2:]
            elif e['type']=='close' and math.dist(at,start)>1e-9:
                segs.append(dict(curve=at+lerp(at,start,1/3)+lerp(at,start,2/3)+start,line=True,smooth=False))
        for i,s in enumerate(segs):
            u=np.asarray(segs[i-1]['curve'][-2:])-np.asarray(segs[i-1]['curve'][4:6])
            v=np.asarray(s['curve'][2:4])-np.asarray(s['curve'][:2])
            angle=math.atan2(abs(float(u[0]*v[1]-u[1]*v[0])),float(np.dot(u,v)))
            s['smooth']=np.linalg.norm(u)*np.linalg.norm(v)>1e-12 and angle<math.radians(1)
        contours.append(segs)
    return outline(contours)


def corpus():
    cases=[];files=[]
    for glyph in ['O','S','a','g','e','s','R','B']:
        path=ROOT/f'Tests/Fixtures/oracle/v1/basic-latin/uni{ord(glyph):04X}/final.json'
        d=json.loads(path.read_text());files.append(path)
        contours=[]
        for c in d['outline']['contours']:
            contours.append(dict(closed=True,nodes=[dict(x=p['x']*1000/d['unitsPerEm'],y=p['y']*1000/d['unitsPerEm'],
                type=p.get('type','offcurve'),smooth=bool(p.get('smooth',False))) for p in c['points']]))
        original=dict(contours=contours)
        cases.append(dict(id='glyph-'+glyph,kind='original-vector',outlines=[original]))
        cases.append(dict(id='refined-'+glyph,kind='raster-refined-vector',outlines=[refined_outline(path.parent,files)]))
        # Exact subdivision creates a controlled, known-redundancy recovery test.
        subdiv=[]
        for segs in spans(original):
            new=[]
            for s in segs:
                if s['line']: new.append(s);continue
                a,b=split(s['curve']);new.extend([dict(curve=a,line=False,smooth=s['smooth']),dict(curve=b,line=False,smooth=True)])
            subdiv.append(new)
        cases.append(dict(id='split-'+glyph,kind='exact-subdivision-control',outlines=[outline(subdiv)]))
    for glyph in ['R','Y']:
        outlines=[]
        for weight in ['regular','bold']:
            path=ROOT/f'Tests/Fixtures/matching/pair-v1/{glyph}-{weight}.outline.json';files.append(path)
            outlines.append(json.loads(path.read_text()))
        cases.append(dict(id='pair-'+glyph,kind='owned-master-pair',outlines=outlines))
    for name,amount in [('mild',.015),('strong',.35)]:
        a=ellipse(220,300);b=ellipse(270,320,.35)
        # Same tangent in each endpoint master, deliberately unequal proportions.
        join=b[0]['curve'][:2]
        b[-1]['curve'][4:6]=lerp(join,b[-1]['curve'][4:6],1-amount)
        b[0]['curve'][2:4]=lerp(join,b[0]['curve'][2:4],1+amount)
        cases.append(dict(id='kink-'+name,kind='synthetic-kink-pair',outlines=[outline([a]),outline([b])]))
    return cases,files


def make_jobs(cases,window):
    jobs=[];groups=[]
    for case in cases:
        masters=[spans(o) for o in case['outlines']]
        for ci,reference in enumerate(masters[0]):
            n=len(reference)
            assert all(len(m[ci])==n for m in masters)
            locks=[i for i in range(n) if any(protected(m[ci],i) for m in masters)]
            locks=sorted(set([0,n]+locks))
            group=dict(id=f"{case['id']}/c{ci}",case=case['id'],contour=ci,n=n,masters=len(masters),locks=locks)
            groups.append(group)
            for start in range(n):
                for end in range(start+1,min(n,start+window)+1):
                    if any(start<k<end for k in locks):continue
                    for mi,master in enumerate(masters):
                        s=master[ci][start:end]
                        if len(s)>1 and any(x['line'] for x in s):continue
                        jobs.append(dict(id=f"{group['id']}/m{mi}/{start}-{end}",group=group['id'],master=mi,start=start,end=end,
                                         curves=[x['curve'] for x in s],line=all(x['line'] for x in s),smooth=s[0]['smooth']))
    return jobs,groups


def select(n,edges,selector):
    if selector=='greedy':
        at=0;result=[]
        while at<n:
            options=[e for e in edges if e['start']==at]
            if not options:return None
            e=min(options,key=lambda x:(-x['end'],x['cost'],x['error'],x['key']))
            result.append(e);at=e['end']
        return result
    best={0:((0,0.0,()),[])}
    for at in range(n):
        if at not in best:continue
        for e in sorted((e for e in edges if e['start']==at),key=lambda x:x['key']):
            old,path=best[at];cost=(old[0]+e['cost'],old[1]+e['error']**2,old[2]+(e['key'],))
            if e['end'] not in best or cost<best[e['end']][0]:best[e['end']]=(cost,path+[e])
    return best[n][1] if n in best else None


def build_outputs(cases,groups,jobs,candidates,verification,tolerances):
    byjob={j['id']:j for j in jobs}
    index={(c['id'],c['tolerance'],c['method']):c for c in candidates}
    valid={(c['id'],c['tolerance'],c['method']):c for c in verification}
    results=[]
    for case in cases:
        for tol in tolerances:
            for method in METHODS:
                for selector in ['greedy','graph']:
                    contours=[[] for _ in case['outlines']];chosen=[];elapsed=0
                    for g in (g for g in groups if g['case']==case['id']):
                        edges=[]
                        for j in (j for j in jobs if j['group']==g['id'] and j['master']==0):
                            start,end=j['start'],j['end'];outputs=[];errors=[];fitmethods=[]
                            for mi in range(g['masters']):
                                jid=f"{g['id']}/m{mi}/{start}-{end}";source=byjob[jid]
                                if end==start+1:
                                    outputs.append(dict(curve=source['curves'][0],line=source['line'],smooth=source['smooth']))
                                    errors.append(0);fitmethods.append('exact-fallback');continue
                                opts=[]
                                for m in (METHODS[:3] if method=='hybrid' else [method]):
                                    key=(jid,tol,m)
                                    if key in valid and valid[key]['accepted']:
                                        c=index[key];opts.append((valid[key]['upper'],m,c))
                                if not opts:break
                                err,m,c=min(opts,key=lambda x:(x[0],x[1]))
                                outputs.append(dict(curve=c['curve'],line=c['line'],smooth=source['smooth']))
                                errors.append(err);fitmethods.append(m)
                            if len(outputs)==g['masters']:
                                edges.append(dict(start=start,end=end,outputs=outputs,error=max(errors),
                                    cost=1+2*int(any(not s['line'] for s in outputs)),key=f'{start:04}-{end:04}',fitters=fitmethods))
                        begin=time.perf_counter_ns();path=select(g['n'],edges,selector);elapsed+=(time.perf_counter_ns()-begin)/1e6
                        assert path
                        for mi in range(g['masters']):contours[mi].append([e['outputs'][mi] for e in path])
                        chosen.extend(dict(contour=g['contour'],start=e['start'],end=e['end'],fitters=e['fitters']) for e in path)
                    outlines=[outline(c) for c in contours]
                    results.append(dict(id=f"{case['id']}:{tol}:{method}:{selector}",case=case['id'],kind=case['kind'],method=method,selector=selector,
                        tolerance=tol,outlines=outlines,sources=case['outlines'],selectionMs=elapsed,chosen=chosen,
                        inputNodes=sum(len(c['nodes']) for c in case['outlines'][0]['contours']),
                        outputNodes=sum(len(c['nodes']) for c in outlines[0]['contours'])))
    return results


def kink_metric(outlines, factor=.5):
    """FontTools-informed local triplet metric; diagnostic, not a port."""
    a,b=[spans(o) for o in outlines];peak=0.0
    for ca,cb in zip(a,b):
        for i,(sa,sb) in enumerate(zip(ca,cb)):
            if not (sa['smooth'] and sb['smooth']):continue
            p=np.asarray(lerp(sa['curve'][:2],sb['curve'][:2],factor))
            incoming=np.asarray(lerp(ca[i-1]['curve'][4:6],cb[i-1]['curve'][4:6],factor))
            outgoing=np.asarray(lerp(sa['curve'][2:4],sb['curve'][2:4],factor))
            u=p-incoming;v=outgoing-p;chord=u+v
            if np.linalg.norm(chord)>1e-12:peak=max(peak,abs(float(u[0]*v[1]-u[1]*v[0]))/float(np.linalg.norm(chord)))
    return peak


def shared_ratio_trial(outlines):
    """Detached target-only experiment; preserve reference and all anchors."""
    a,b=[spans(o) for o in outlines]
    for ca,cb in zip(a,b):
        for i,(sa,sb) in enumerate(zip(ca,cb)):
            if not (sa['smooth'] and sb['smooth']) or sa['line'] or ca[i-1]['line'] or sb['line'] or cb[i-1]['line']:continue
            pa=np.asarray(sa['curve'][:2]);pb=np.asarray(sb['curve'][:2])
            ia=np.linalg.norm(pa-np.asarray(ca[i-1]['curve'][4:6]));oa=np.linalg.norm(np.asarray(sa['curve'][2:4])-pa)
            ib=np.linalg.norm(pb-np.asarray(cb[i-1]['curve'][4:6]));ob=np.linalg.norm(np.asarray(sb['curve'][2:4])-pb)
            if min(ia,oa,ib,ob)<1e-12:continue
            ratio=oa/ia
            # Least movement along existing tangent directions with out=ratio*in.
            length=(ib+ratio*ob)/(1+ratio*ratio)
            cb[i-1]['curve'][4:6]=(pb+(np.asarray(cb[i-1]['curve'][4:6])-pb)*(length/ib)).tolist()
            sb['curve'][2:4]=(pb+(np.asarray(sb['curve'][2:4])-pb)*(ratio*length/ob)).tolist()
    return [outlines[0],outline(b)]


def svg(o):
    paths=[]
    for segs in spans(o):
        s=f"M {segs[0]['curve'][0]} {-segs[0]['curve'][1]}"
        for seg in segs:
            c=seg['curve']
            s+=f' L {c[6]} {-c[7]}' if seg['line'] else f' C {c[2]} {-c[3]} {c[4]} {-c[5]} {c[6]} {-c[7]}'
        paths.append(s+' Z')
    return ' '.join(paths)


def render_report(out,cases,results,summary):
    rows=[]
    for r in results:
        if r['tolerance']!=1 or r['selector']!='greedy':continue
        source=r['sources'][0];target=r['outlines'][0]
        pts=[(p['x'],p['y']) for c in source['contours'] for p in c['nodes']]
        x=min(p[0] for p in pts)-25;y=-max(p[1] for p in pts)-25
        w=max(p[0] for p in pts)-x+25;h=-min(p[1] for p in pts)-y+25
        status=r['checks']['valid']
        dots=''.join(f'<circle cx="{p["x"]}" cy="{-p["y"]}" r="3" fill="#0869b7"/>' for c in target['contours'] for p in c['nodes'] if p['type']!='offcurve')
        rows.append(f'<article><h3>{html.escape(r["case"])} · {html.escape(r["method"])}</h3>'
            f'<p>{r["inputNodes"]} → {r["outputNodes"]} nodes/master · {"PASS" if status else "REFUSED"}</p>'
            f'<svg viewBox="{x} {y} {w} {h}"><path d="{svg(source)}" fill="none" stroke="#aaa" stroke-width="3"/>'
            f'<path d="{svg(target)}" fill="none" stroke="#0869b7" stroke-width="1"/>{dots}</svg>'
            f'<p>{html.escape(str(r["checks"]["reasons"]))}</p></article>')
    table=[]
    for method in REPORT_METHODS:
        def total(kind):return sum(r['outputNodes'] for r in results if r['kind']==kind and r['method']==method and r['tolerance']==1 and r['selector']=='greedy')
        s=next(s for s in summary if s['method']==method and s['selector']=='greedy' and s['tolerance']==1)
        timing='combined cost; not timed as a pipeline' if s['candidateMedianMs'] is None else f"{s['candidateMedianMs']*1000:.2f} μs"
        table.append(f'<tr><td>{method}</td><td>{total("original-vector")}</td><td>{total("raster-refined-vector")}</td><td>{total("exact-subdivision-control")}</td><td>{timing}</td></tr>')
    page='<!doctype html><meta charset="utf-8"><title>Beztrace curve optimization benchmark</title><style>body{font:15px/1.5 system-ui;max-width:1450px;margin:30px auto;padding:20px;background:#fafafa} .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}article,section{background:white;border:1px solid #ddd;padding:16px}svg{width:100%;height:230px}pre{white-space:pre-wrap}table{border-collapse:collapse;width:100%;background:white}td,th{text-align:left;padding:12px;border-bottom:1px solid #ddd}h3{font-size:14px}@media(max-width:850px){.grid{grid-template-columns:repeat(2,1fr)}}</style>'
    page+='<h1>Beztrace: measured curve optimization comparison</h1><p>28 local samples · native arm64 · tolerances 0.5 / 1 / 2 units · 11 timed calls after 2 warmups · identical source spans, protected landmarks and acceptance checks.</p>'
    page+='<section><h2>Finding</h2><p><strong>Swift sequential hybrid: Levien proposals, independent source verification, refined least-squares fallback.</strong> Levien recovers more deliberate redundancy; least squares finds an additional valid lowercase e merge. All fitters give the same result on the eight already-clean original glyphs. Graph selection has no node-count advantage over greedy on this sample.</p><p>The large reduction occurs on exact-subdivision controls. These results do not establish a similar reduction on typical production artwork. This is vector optimization of raster-derived/clean paths, not an end-to-end raster tracing competition.</p></section>'
    page+='<h2>1-unit comparison — total nodes including handles</h2><table><tr><th>Candidate fitter</th><th>8 clean glyphs<br>322 input nodes</th><th>8 raster-refined glyphs<br>328 input nodes</th><th>8 subdivision controls<br>559 input nodes</th><th>Median fitting call<br>multi-span attempts</th></tr>'+''.join(table)+'</table>'
    page+='<p>Raw fitting timings exclude verification for the legacy Swift and Rust methods. The hybrid-swift timing includes source preparation, proposal ranking and independent verification; do not compare those columns as equivalent workloads. Hybrid is the historical exhaustive candidate union; hybrid-swift is the actual sequential production implementation. Overlays use existing greedy selection. Graph remains research-only.</p>'
    pipelines=[s for s in summary if s['tolerance']==1 and s['selector']=='greedy' and s['method'] in ['refined-swift-verified','hybrid-swift']]
    page+='<h2>Comparable Swift fit + verification workload</h2><table><tr><th>Implementation</th><th>Passing cases</th><th>Nodes on passing cases</th><th>Median multi-span call</th></tr>'
    for s in pipelines:
        page+=f"<tr><td>{s['method']}</td><td>{s['accepted']}/{s['cases']}</td><td>{s['nodesOnAccepted']}</td><td>{s['candidateMedianMs']:.3f} ms</td></tr>"
    page+='</table><p>Both rows include immutable source preparation, source samples, fitting and the same verifier. Proposal-only timings above measure a different workload. These are local microbenchmarks; they do not establish an end-to-end application speedup.</p>'
    smooth_rows=[]
    smoothing_inputs={r['id']:r['request'] for r in json.loads((out/'joint-smoothing-inputs.json').read_text())}
    for row in json.loads((out/'joint-smoothing.json').read_text()):
        report=row['result']['report'];request=smoothing_inputs[row['id']]
        before=report.get('beforeMaximumTangencyResidual');after=report.get('afterMaximumTangencyResidual')
        bound=report.get('proposalDeviation',{}).get('upperBound')
        fmt=lambda value: '—' if value is None else f'{value:.6g}'
        smooth_rows.append(f"<tr><td>{html.escape(row['id'].split(':')[0])}</td><td>{request['fitTolerance']:g}</td><td>{report['status']}</td><td>{fmt(before)} → {fmt(after)}</td><td>{fmt(bound)}</td><td>{len(report['changedHandles'])}</td><td>{statistics.median(row['timesMs']):.3f} ms</td></tr>")
    page+='<h2>Actual Swift joint smoothing</h2><p>Reference and all on-curves/types/flags/order are fixed. Every proposal is verified against the immutable original target after all changes. A refusal returns the unmodified target. Bounds below describe the proposed repair, including on refusal. Residuals are maxima across 201 positions.</p><table><tr><th>Pair</th><th>Tolerance</th><th>Status</th><th>Residual before → after</th><th>Proposed source upper bound</th><th>Returned handle changes</th><th>Full smoothing call</th></tr>'+''.join(smooth_rows)+'</table><p>Two warmups and eleven timed calls. No graph selection or node insertion/removal is involved. Single-master samples are not applicable. <a href="joint-smoothing-inputs.json">Exact requests</a> · <a href="joint-smoothing.json">Results and timings</a></p>'
    page+='<h2>Compatibility and smoothing</h2><p>Actual Swift joint smoothing runs after the greedy hybrid. A requested smoothing refusal counts as refusal even when retaining the original target is geometrically valid. See <a href="joint-smoothing.json">joint smoothing reports and timings</a>. The separate historical experiment follows. Both R/Y pairs keep their structures. The strong synthetic kink already fails the identity baseline. Target-only shared-ratio repair reduces the mild midpoint residual from 0.221u to near zero within a 0.790u source bound, preserving the reference. The tested strong repair has an 18.351u source bound and is refused at 1u; this is not proof that every possible repair would fail. Full topology/interpolation validation is sampled, not a continuous font qualification.</p>'
    page+='<p><a href="results.json">All per-case results</a> · <a href="summary.json">All tolerances</a> · <a href="verification.json">Independent span checks</a> · <a href="smoothing-trials.json">Smoothing trials</a> · <a href="receipt.json">Hashes and environment</a></p>'
    page+='<h2>1-unit overlays</h2><p>Original grey, candidate blue; blue circles are retained on-curves. Refused candidates remain visible as research evidence.</p><div class="grid">'+''.join(rows)+'</div>'
    (out/'index.html').write_text(page)


def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--repeats',type=int,default=3)
    p.add_argument('--window',type=int,default=6);p.add_argument('--reuse',action='store_true')
    a=p.parse_args();out=a.output.resolve()
    if not a.reuse:out.mkdir(parents=True,exist_ok=False)
    elif not out.is_dir():raise ValueError('--reuse requires existing output')
    tolerances=[.5,1.,2.];cases,files=corpus();jobs,groups=make_jobs(cases,a.window)
    payload=dict(jobs=jobs,tolerances=tolerances,repeats=a.repeats)
    if a.reuse and json.loads((out/'inputs.json').read_text())!=payload:
        raise ValueError('Cached input/configuration differs; choose a new output directory')
    save(out/'inputs.json',payload);save(out/'cases.json',cases)
    driver=ROOT/'.build/curve-benchmark-tools/driver';reference=ROOT/'.build/curve-benchmark-reference/release/beztrace-curve-benchmark-reference'
    timings={}
    for label,binary,args in [('swift',driver,['fit']),('kurbo',reference,[])]:
        path=out/f'{label}-candidates.json';start=time.monotonic()
        if not (a.reuse and path.exists()):path.write_text(command([binary,*args],payload=payload))
        timings[label]=time.monotonic()-start
        print(f'{label} candidates complete ({timings[label]:.1f}s)',flush=True)
    candidates=json.loads((out/'swift-candidates.json').read_text())+json.loads((out/'kurbo-candidates.json').read_text())
    byjob={j['id']:j for j in jobs}
    path=out/'verification.json'
    if not (a.reuse and path.exists()):
        checks=json.loads(command([driver,'verify',out/'inputs.json'],payload=candidates))
        lookup={(c['id'],c['tolerance'],c['method']):c for c in candidates}
        for check in checks:
            check.update(quality(byjob[check['id']],lookup[(check['id'],check['tolerance'],check['method'])]))
            if check['accepted'] and (check['extraInflection'] or check['orderedError']>check['tolerance']):
                check['accepted']=False;check['reason']='extra-inflection' if check['extraInflection'] else 'ordered-arc-distance'
        save(path,checks)
    checks=json.loads(path.read_text());print(f'{len(checks)} independent span checks complete',flush=True)
    results=build_outputs(cases,groups,jobs,candidates,checks,tolerances)
    # Explicit, reference-locked postprocessing of the existing greedy result.
    # Original source outlines survive simplification and are supplied unchanged.
    smooth_jobs=[]
    for r in results:
        if r['method']=='hybrid-swift' and r['selector']=='greedy' and len(r['outlines'])==2:
            smooth_jobs.append(dict(id=r['id'],repeats=a.repeats,request=dict(schemaVersion=1,unitsPerEm=1000,
                fitTolerance=r['tolerance'],reference=r['outlines'][0],target=r['outlines'][1],sourceTarget=r['sources'][1])))
    smooth_results=json.loads(command([driver,'smooth'],payload=smooth_jobs,timeout=1200))
    save(out/'joint-smoothing-inputs.json',smooth_jobs);save(out/'joint-smoothing.json',smooth_results)
    smooth_lookup={r['id']:r for r in smooth_results}
    smoothed=[]
    for r in results:
        if r['method']!='hybrid-swift' or r['selector']!='greedy':continue
        result=dict(r);result['method']='hybrid-swift-smoothed';result['id']=r['id'].replace(':hybrid-swift:',':hybrid-swift-smoothed:');result['jointSmoothingApplicable']=len(r['outlines'])==2
        if len(r['outlines'])==2:
            trial=smooth_lookup[r['id']]['result']
            assert trial['reference']==r['outlines'][0], 'Smoothing altered reference'
            for c,d in zip(trial['target']['contours'],r['outlines'][1]['contours']):
                assert len(c['nodes'])==len(d['nodes'])
                for x,y in zip(c['nodes'],d['nodes']):
                    assert x['type']==y['type'] and x['smooth']==y['smooth']
                    if x['type']!='offcurve':assert x==y
            result['outlines']=[trial['reference'],trial['target']]
            result['jointSmoothingReport']=trial['report']
        smoothed.append(result)
    results.extend(smoothed)
    legacy_jobs=[dict(id=f"{c['id']}:{t}:legacy-cleanup:legacy",outlines=c['outlines'],sources=c['outlines'],tolerance=t) for c in cases for t in tolerances]
    legacy=json.loads(command([driver,'legacy'],payload=legacy_jobs))
    for case in cases:
        for tol in tolerances:
            results.append(dict(id=f"{case['id']}:{tol}:identity:identity",case=case['id'],kind=case['kind'],method='identity',selector='identity',tolerance=tol,
                outlines=case['outlines'],sources=case['outlines'],inputNodes=sum(len(c['nodes']) for c in case['outlines'][0]['contours']),
                outputNodes=sum(len(c['nodes']) for c in case['outlines'][0]['contours'])))
            id=f"{case['id']}:{tol}:legacy-cleanup:legacy";o=legacy[id]
            results.append(dict(id=id,case=case['id'],kind=case['kind'],method='legacy-cleanup',selector='legacy',tolerance=tol,outlines=o,sources=case['outlines'],
                inputNodes=sum(len(c['nodes']) for c in case['outlines'][0]['contours']),outputNodes=sum(len(c['nodes']) for c in o[0]['contours'])))
    smoothing=[]
    for case in cases:
        if len(case['outlines'])!=2:continue
        for tol in tolerances:
            trial=shared_ratio_trial(case['outlines'])
            smoothing.append(dict(id=f"{case['id']}:{tol}:ratio-trial",outlines=trial,sources=case['outlines'],tolerance=tol,
                beforeMidpointResidual=kink_metric(case['outlines']),afterMidpointResidual=kink_metric(trial),
                referenceUnchanged=trial[0]==case['outlines'][0]))
    smoothing_checks=json.loads(command([driver,'outlines'],payload=[{k:r[k] for k in ['id','outlines','sources','tolerance']} for r in smoothing]))
    for r,c in zip(smoothing,smoothing_checks):r['checks']=c
    save(out/'smoothing-trials.json',smoothing)
    print(f'Validating {len(results)} complete outlines/pairs...',flush=True)
    outline_checks=json.loads(command([driver,'outlines'],payload=[{k:r[k] for k in ['id','outlines','sources','tolerance']} for r in results],timeout=1200))
    lookup={c['id']:c for c in outline_checks}
    for r in results:
        r['checks']=lookup[r['id']]
        if r.get('jointSmoothingReport',{}).get('status')=='refused':
            r['checks']['valid']=False;r['checks']['reasons'].append('joint smoothing refused: '+r['jointSmoothingReport']['reason'])
    save(out/'results.json',results)
    summary=[]
    for tol in tolerances:
        for method,selector in [(m,s) for m in REPORT_METHODS for s in (['greedy'] if m=='hybrid-swift-smoothed' else ['greedy','graph'])]+[('legacy-cleanup','legacy'),('identity','identity')]:
            rs=[r for r in results if r['tolerance']==tol and r['method']==method and r['selector']==selector]
            passing=[r for r in rs if r['checks']['valid']]
            fits=[c for c in candidates if c['tolerance']==tol and c['method']==method and byjob[c['id']]['end']-byjob[c['id']]['start']>1]
            summary.append(dict(tolerance=tol,method=method,selector=selector,cases=len(rs),accepted=len(passing),
                nodesOnAccepted=sum(r['outputNodes'] for r in passing),inputNodesOnAccepted=sum(r['inputNodes'] for r in passing),
                nodesWithRefusalsKeptOriginal=sum(r['outputNodes'] if r['checks']['valid'] else r['inputNodes'] for r in rs),
                candidateMedianMs=statistics.median([statistics.median(c['timesMs']) for c in fits]) if fits else None,
                acceptedSpanCandidates=sum(c['accepted'] for c in checks if c['method']==method and c['tolerance']==tol),
                refusedCases=[r['case'] for r in rs if not r['checks']['valid']]))
    save(out/'summary.json',summary)
    groups_summary=[]
    for kind in sorted({c['kind'] for c in cases}):
        for method in REPORT_METHODS:
            rs=[r for r in results if r['kind']==kind and r['method']==method and r['tolerance']==1 and r['selector']=='greedy']
            groups_summary.append(dict(kind=kind,method=method,cases=len(rs),accepted=sum(r['checks']['valid'] for r in rs),
                inputNodes=sum(r['inputNodes'] for r in rs),outputNodes=sum(r['outputNodes'] for r in rs)))
    save(out/'groups-summary.json',groups_summary)
    receipt=dict(revision=command(['git','rev-parse','HEAD']).strip(),branch=command(['git','branch','--show-current']).strip(),
        machine=platform.platform(),architecture=platform.machine(),swift=command(['swift','--version']).strip(),rust=command(['rustc','+1.88.0','--version']).strip(),
        repeats=a.repeats,warmups=2,tolerances=tolerances,window=a.window,spanJobs=len(jobs),samples=len(cases),
        sourceFiles={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},
        driverFiles={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted((ROOT/'scripts/curve_benchmark').rglob('*')) if f.is_file() and '__pycache__' not in str(f)},
        coreFiles={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted((ROOT/'Sources/BezierTraceCore').glob('*.swift'))},
        binaries={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [driver,reference]},
        processSeconds=timings,scope='Vector optimization sample; no raster-tracing accuracy, native font or release qualification claim')
    save(out/'receipt.json',receipt);render_report(out,cases,results,summary)
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
