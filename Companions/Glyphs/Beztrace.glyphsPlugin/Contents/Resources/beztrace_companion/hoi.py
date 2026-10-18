# Copyright 2026 Thierry Charbonnel (thierryc), beztrace contributors
# SPDX-License-Identifier: Apache-2.0
# Native evaluator adapted from dekink-glyphs4 f6c33d969732716698e8a10e0714e1ec4b74a118.
# Material changes: no MCP/exec, cancellable detached trials, movement-first
# ranking, full-outline checks, import verification and no live mutation.
"""Native HOI preparation generator. Every step runs on the AppKit main thread."""
import copy
import math
import time
from . import hoi_geometry as geo
from .contract import CompanionError, segments, signed_area
from .engine import Cancelled
from .matching_native import call


def shape_samples(paths):
    result=[]
    for path in paths:
        for start,controls,end in segments(path):
            points=[start]+controls+[end]
            for k in range(17):
                t=k/16; u=1-t
                weights=[u,t] if not controls else [u**3,3*u*u*t,3*u*t*t,t**3]
                result.append(tuple(sum(w*p[axis] for w,p in zip(weights,points)) for axis in ('x','y')))
    return result


def movement_bound(a,b,accuracy):
    """Conservative positional deviation of corresponding cubic sections.

    The difference curve lies in the convex hull of its control vectors.
    Subdivision tightens that bound without missing a peak between samples.
    """
    def bound(points,depth=0):
        upper=max(math.hypot(*p) for p in points)
        def mid(p,q): return tuple((x+y)/2 for x,y in zip(p,q))
        ab,bc,cd=mid(points[0],points[1]),mid(points[1],points[2]),mid(points[2],points[3])
        abc,bcd=mid(ab,bc),mid(bc,cd); center=mid(abc,bcd)
        lower=max(math.hypot(*p) for p in (points[0],center,points[3]))
        if depth==12 or upper-lower<=accuracy: return upper
        return max(bound([points[0],ab,abc,center],depth+1),bound([center,bcd,cd,points[3]],depth+1))
    maximum=0.
    for p,q in zip(a,b):
        for (s,c,e),(ss,cc,ee) in zip(segments(p),segments(q)):
            if not c:
                maximum=max(maximum,math.dist((s['x'],s['y']),(ss['x'],ss['y'])),math.dist((e['x'],e['y']),(ee['x'],ee['y'])))
            else:
                delta=[(x['x']-y['x'],x['y']-y['y']) for x,y in zip([s]+c+[e],[ss]+cc+[ee])]
                maximum=max(maximum,bound(delta))
    return maximum


def nesting(paths):
    polygons=[shape_samples([p]) for p in paths]
    def inside(p,poly):
        result=False
        for a,b in zip(poly,poly[1:]+poly[:1]):
            if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]: result=not result
        return result
    return [sum(inside(poly[0],other) for j,other in enumerate(polygons) if j!=i) for i,poly in enumerate(polygons)]


def shape_valid(paths,signs,depths=None):
    if len(paths)!=len(signs) or depths is not None and nesting(paths)!=depths: return False
    edges=[]
    for path,sign in zip(paths,signs):
        if path.get('closed') is not True: return False
        if signed_area(path)*sign <= 1e-9: return False
        points=shape_samples([path])
        if not all(all(math.isfinite(v) for v in p) for p in points): return False
        # Sweep sampled edges in x order, including intersections with counters.
        poly=[]
        for p in points:
            if not poly or math.dist(poly[-1],p)>1e-12: poly.append(p)
        if math.dist(poly[0],poly[-1])<1e-12: poly.pop()
        ci=len(edges)
        for i,(a,b) in enumerate(zip(poly,poly[1:]+poly[:1])):
            edges.append((min(a[0],b[0]),max(a[0],b[0]),min(a[1],b[1]),max(a[1],b[1]),ci,i,len(poly),a,b))
    active=[]
    for edge in sorted(edges,key=lambda e:(e[0],e[2],e[4],e[5])):
        active=[e for e in active if e[1]>=edge[0]]
        for other in active:
            if edge[3]<other[2] or other[3]<edge[2]: continue
            if edge[4]==other[4] and (abs(edge[5]-other[5])==1 or {edge[5],other[5]}=={0,edge[6]-1}): continue
            a,b=edge[-2:]; c,d=other[-2:]; ab=geo.sub(b,a); cd=geo.sub(d,c)
            if geo.cross(ab,geo.sub(c,a))*geo.cross(ab,geo.sub(d,a)) < -1e-12 and geo.cross(cd,geo.sub(a,c))*geo.cross(cd,geo.sub(b,c)) < -1e-12: return False
        active.append(edge)
    return True


class NativeEvaluator:
    def __init__(self,host): self.host=host
    def clone(self,stage):
        # The stage font is already detached and retains the complete read-only
        # context. A candidate needs fresh glyph/layer/node objects, not another
        # copy of every unrelated glyph. Never parent a trial to a live font.
        ctx=stage['context']
        if self.host.same(stage['font'],ctx['font']):
            raise CompanionError('HOI trials require a detached font context')
        font=stage['font']; glyph=call(stage['layers'][0].parent,'copy')
        call(glyph,'setParent_',font)
        manager=glyph.undoManager()
        if manager is not None:
            if self.host.same(manager,ctx['glyph'].undoManager()):
                raise CompanionError('Native HOI copy shares the source Undo manager')
            manager.disableUndoRegistration()
        return dict(font=font,layers=[glyph.layers[t.owner.layerId] for t in ctx['targets']],context=ctx,evaluation_glyph=glyph)
    def endpoints(self,stage): return self.host.stage_paths(stage)
    def existing(self,stage): return self.host.existing_hoi(stage)
    def set_existing(self,stage,entry):
        from .matching_contract import validate_hoi_settings
        from .native import _value
        validate_hoi_settings(entry['settings'])
        node=stage['layers'][entry['master']].paths[entry['contour']].nodes[entry['node']]
        value=dict(call(node,'attributeForKey_','hoi') or {}); axis=stage['context']['axis']['tag']
        if axis in value and _value(value[axis])!=_value(entry['settings']):
            raise CompanionError('Imported HOI conflicts with an existing local correction')
        value[axis]=entry['settings']; call(node,'setAttribute_forKey_',value,'hoi')
    def set_ip(self,stage,entry):
        node=stage['layers'][entry['master']].paths[entry['contour']].nodes[entry['node']]
        old=call(node,'attributeForKey_','hoi')
        current={} if old is None else dict(old)
        axis=stage['context']['axis']['tag']
        from .native import _value
        if axis in current and _value(current[axis])!=_value({'ip':entry['ip']}):
            raise CompanionError('Existing local HOI cannot be overwritten')
        current[axis]={'ip':entry['ip']}
        call(node,'setAttribute_forKey_',current,'hoi')
    def has_local(self,stage,ci,indices):
        axis=stage['context']['axis']['tag']
        return any(axis in (call(layer.paths[ci].nodes[ni],'attributeForKey_','hoi') or {}) for layer in stage['layers'] for ni in indices)
    def sample(self,stage,factor):
        import objc
        ctx=stage['context']; locations=ctx['axis']['locations']
        low=0 if locations[0]<locations[1] else 1; high=1-low
        lower,upper=stage['layers'][low],stage['layers'][high]
        window=objc.lookUpClass('HOIWindow').alloc().initWithLayer_axisTag_extraHandles_(lower,ctx['axis']['tag'],[])
        span=call(window,'upper')
        if span is None or not self.host.same(call(span,'upperLayer'),upper):
            raise CompanionError('Native HOI evaluator selected an unexpected master span')
        call(span,'deriveHOIStack')
        lo,hi=float(call(span,'originLocation')),float(call(span,'otherLocation'))
        if abs(lo-min(locations))>1e-6 or abs(hi-max(locations))>1e-6:
            raise CompanionError('Native HOI evaluator selected unexpected axis locations')
        layer=call(lower,'copy'); call(layer,'setParent_',None)
        call(objc.lookUpClass('HOI').alloc().init(),'applyHOISpan_toInstanceLayer_atLocation_',span,layer,lo+(hi-lo)*factor)
        return [self.host.path_data(path) for path in layer.paths]


def prepare(stage,host,settings,cancel,imported_entries=(),evaluator=None,*,imported_existing=()):
    """Yield progress between native samples; return a verified detached stage.

    Evaluator is a test seam, not an exported scripting capability. Master
    geometry and unrelated attributes are never changed by this generator.
    """
    evaluator=evaluator or NativeEvaluator(host)
    upm=stage['context']['unitsPerEm']; unit=upm/1000
    threshold=settings['kinkThreshold']*unit; allowance=.001*unit
    max_move=settings['maxShapeMovement']*unit
    deadline=time.monotonic()+60
    def check():
        if cancel.is_set(): raise Cancelled('Matching cancelled')
        if time.monotonic()>deadline: raise CompanionError('Native HOI preparation exceeded 60 seconds')
    endpoints=evaluator.endpoints(stage)
    low=0 if stage['context']['axis']['locations'][0]<stage['context']['axis']['locations'][1] else 1
    joins=[]; excluded=[]
    for ci,(a,b) in enumerate(zip(*endpoints)):
        for ni,(p,q) in enumerate(zip(a['nodes'],b['nodes'])):
            if p['type']=='offcurve' or not (p['smooth'] and q['smooth']): continue
            n=len(a['nodes']); indices=[(ni+n-1)%n,ni,(ni+1)%n]
            triples=[[(path['nodes'][i]['x'],path['nodes'][i]['y']) for i in indices] for path in (a,b)]
            metrics=[geo.metric(t) for t in triples]
            key='%d/%d'%(ci,ni)
            if any(m['folded'] or m['degenerate'] for m in metrics):
                excluded.append(dict(id=key,reason='folded or degenerate endpoint tangency')); continue
            joins.append(dict(id=key,contour=ci,node=ni,indices=indices,triples=triples,
                              source=metrics,limit=geo.verification_limit(metrics,allowance)))
    factors=[i/100 for i in range(101)]
    signs=[1 if signed_area(p)>0 else -1 for p in endpoints[low]]
    depths=nesting(endpoints[low])
    def measure(working,positions):
        rows=[]; peaks={j['id']:0. for j in joins}; invalid=set()
        for factor in positions:
            check(); paths=evaluator.sample(working,factor)
            if len(paths)!=len(endpoints[0]) or any(len(p['nodes'])!=len(q['nodes']) or
                    [n['type'] for n in p['nodes']]!=[n['type'] for n in q['nodes']] for p,q in zip(paths,endpoints[0])):
                raise CompanionError('Native HOI changed outline structure')
            if not shape_valid(paths,signs,depths): raise CompanionError('Native interpolation produced invalid sampled outline geometry')
            if factor in (0.,1.):
                wanted=endpoints[low if factor==0 else 1-low]
                for p,q in zip(paths,wanted):
                    for a,b in zip(p['nodes'],q['nodes']):
                        if a['type']!=b['type'] or max(abs(a[k]-b[k]) for k in ('x','y'))>allowance:
                            raise CompanionError('HOI changed an endpoint master')
            for j in joins:
                ns=paths[j['contour']]['nodes']; triple=[(ns[i]['x'],ns[i]['y']) for i in j['indices']]
                m=geo.metric(triple)
                if m['folded'] or m['degenerate']: invalid.add(j['id'])
                else: peaks[j['id']]=max(peaks[j['id']],m['error_u'])
            rows.append(dict(factor=factor,paths=paths,shape=shape_samples(paths)))
            yield dict(stage='Checking native interpolation',factor=factor)
        return dict(rows=rows,peaks=peaks,invalid=invalid)
    interleaved_factors=[(i+.5)/100 for i in range(100)]
    all_factors=factors+interleaved_factors
    baseline=yield from measure(stage,all_factors)
    working=evaluator.clone(stage); entries=[]; reports=[]; unresolved=list(excluded)
    preserved=getattr(evaluator,'existing',lambda stage:[])(stage)
    for entry in imported_existing:
        check(); evaluator.set_existing(working,entry)
        if entry not in preserved: preserved.append(copy.deepcopy(entry))
    for entry in imported_entries:
        check(); evaluator.set_ip(working,entry)
        if not any(all(p[k]==entry[k] for k in ('master','contour','node')) for p in preserved): entries.append(copy.deepcopy(entry))
    if imported_entries or imported_existing: imported_before=yield from measure(working,all_factors)
    else: imported_before=baseline
    current=imported_before
    for join in joins:
        check(); key=join['id']; before=current['peaks'][key]
        # Detection and verification are separate limits. Preserved endpoint
        # residuals may exceed the detection threshold; reducing the sampled
        # maximum below those endpoints would be mathematically impossible.
        if key not in current['invalid'] and (before<=threshold or before<=join['limit']): continue
        if evaluator.has_local(working,join['contour'],join['indices']):
            unresolved.append(dict(id=key,reason='existing local HOI requires manual review',peak=before)); continue
        valid=[]
        try: proposals=geo.candidates(*join['triples'],allowance)
        except ValueError as exc:
            unresolved.append(dict(id=key,reason=str(exc))); continue
        for proposal in proposals:
            check(); trial=evaluator.clone(working); trial_entries=[]; converged=True
            for local,target in proposal['targets'].items():
                entry=dict(master=low,contour=join['contour'],node=join['indices'][local],ip=list(target))
                # Calibration writes only detached copies; each attempt starts
                # from the same pre-candidate state, so existing HOI is preserved.
                def write(value):
                    nonlocal trial
                    trial=evaluator.clone(working)
                    for previous in trial_entries: evaluator.set_ip(trial,previous)
                    candidate=dict(entry,ip=list(value)); evaluator.set_ip(trial,candidate)
                    entry['ip']=list(value)
                def read():
                    p=evaluator.sample(trial,.5)[entry['contour']]['nodes'][entry['node']]
                    return p['x'],p['y']
                calibrated=geo.calibrate_midpoint(target,write,read,min(.0001*unit,allowance/10))
                converged=converged and calibrated['converged']; trial_entries.append(copy.deepcopy(entry))
            if not converged: continue
            try: after=yield from measure(trial,all_factors)
            except Cancelled: raise
            except CompanionError: continue
            if after['invalid'] or after['peaks'][key]>join['limit']: continue
            if any(after['peaks'][j['id']]>current['peaks'][j['id']]+allowance for j in joins if j['id']!=key): continue
            maximum=0.; squares=0.; count=0
            for a,b in zip(after['rows'],baseline['rows']):
                maximum=max(maximum,movement_bound(a['paths'],b['paths'],allowance))
                for p,q in zip(a['shape'],b['shape']):
                    distance=math.dist(p,q); maximum=max(maximum,distance); squares+=distance*distance; count+=1
            if maximum>max_move: continue
            score=(maximum,math.sqrt(squares/max(1,count)),len(trial_entries),proposal['strategy'])
            valid.append((score,trial,after,trial_entries,proposal['strategy']))
        if not valid:
            unresolved.append(dict(id=key,reason='no verified candidate within the shape movement limit',peak=before)); continue
        score,working,current,added,strategy=min(valid,key=lambda item:item[0])
        entries.extend(added)
        reports.append(dict(id=key,strategy=strategy,entryCount=len(added),before=before,after=current['peaks'][key],
                            maximumDeviation=score[0],rmsDeviation=score[1],verificationLimit=join['limit']))
    final=yield from measure(working,factors)
    interleaved=yield from measure(working,interleaved_factors)
    for join in joins:
        key=join['id']
        if key in final['invalid'] or key in interleaved['invalid']:
            unresolved.append(dict(id=key,reason='folded or degenerate sampled tangency')); continue
        if any(r['id']==key for r in reports):
            if max(final['peaks'][key],interleaved['peaks'][key])>join['limit']:
                unresolved.append(dict(id=key,reason='combined/interleaved repair verification failed'))
        elif max(final['peaks'][key],interleaved['peaks'][key])>baseline['peaks'][key]+allowance:
            unresolved.append(dict(id=key,reason='neighboring join regressed'))
    # Independently check movement at the interleaved locations, including
    # imported settings. Imported verification claims are never read.
    maximum=0.; squares=0.; count=0
    for a,b in zip(final['rows']+interleaved['rows'],baseline['rows']):
        maximum=max(maximum,movement_bound(a['paths'],b['paths'],allowance))
        for p,q in zip(a['shape'],b['shape']):
            distance=math.dist(p,q); maximum=max(maximum,distance); squares+=distance*distance; count+=1
    if maximum>max_move: unresolved.append(dict(id='outline',reason='combined HOI exceeds shape movement limit',maximumDeviation=maximum))
    checks=[dict(id=j['id'],limit=j['limit'],before=baseline['peaks'][j['id']],
                 finalPeak=max(final['peaks'][j['id']],interleaved['peaks'][j['id']])) for j in joins]
    return dict(stage=working,entries=entries,preserved=preserved,reports=reports,unresolved=unresolved,joinChecks=checks,
                sampledOnly=True,nativeVerified=not unresolved,sampleCount=201,
                maximumDeviation=maximum,rmsDeviation=math.sqrt(squares/max(1,count)),
                baseline=baseline['rows'],
                preview=[dict(factor=row['factor'],paths=row['paths']) for row in final['rows']])


def verify_committed(stage,host,report,settings,cancel):
    """Read-only checks on the committed glyph before its Undo group closes."""
    evaluation=NativeEvaluator(host); unit=stage['context']['unitsPerEm']/1000
    endpoints=evaluation.endpoints(stage)
    low=0 if stage['context']['axis']['locations'][0]<stage['context']['axis']['locations'][1] else 1
    signs=[1 if signed_area(p)>0 else -1 for p in endpoints[low]]
    depths=nesting(endpoints[low])
    limits={item['id']:item['finalPeak']+.001*unit for item in report['joinChecks']}
    positions=[i/100 for i in range(101)]+[(i+.5)/100 for i in range(100)]
    for factor,before in zip(positions,report['baseline']):
        if cancel.is_set(): raise Cancelled('Matching cancelled during Apply')
        paths=evaluation.sample(stage,factor)
        if len(paths)!=len(endpoints[0]) or any([n['type'] for n in p['nodes']]!=[n['type'] for n in q['nodes']] for p,q in zip(paths,endpoints[0])):
            raise CompanionError('Committed HOI changed outline structure')
        if not shape_valid(paths,signs,depths): raise CompanionError('Committed HOI produced invalid sampled geometry')
        if movement_bound(paths,before['paths'],.001*unit)>settings['maxShapeMovement']*unit:
            raise CompanionError('Committed HOI exceeds the shape movement limit')
        for key,limit in limits.items():
            ci,ni=map(int,key.split('/')); ns=paths[ci]['nodes']; n=len(ns)
            metric=geo.metric([(ns[i]['x'],ns[i]['y']) for i in ((ni+n-1)%n,ni,(ni+1)%n)])
            if metric['folded'] or metric['degenerate'] or metric['error_u']>limit:
                raise CompanionError('Committed HOI failed tangency verification')
