# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Versioned matching transport and file exchange; no native imports."""
import copy
import json
import math
from pathlib import Path
from .contract import CompanionError, number, validate_schema, segments, _unique
from .engine import run_process, Cancelled

MATCH_API_VERSION = 1
MAX_FILE = 16 * 1024 * 1024


class MatchingDiagnosticError(CompanionError):
    """Preserve bounded engine evidence for Details and detached preview markers."""
    def __init__(self,message,diagnostic=None):
        super().__init__(message)
        self.diagnostic=copy.deepcopy(diagnostic)


def engine_failure(err):
    try:
        detail=decode(err)['error']
        message=detail['message']
        if not isinstance(message,str): raise ValueError('Invalid error message')
        diagnostic=detail.get('diagnostic')
        if diagnostic is not None:
            schema=json.loads((Path(__file__).parents[1]/'match-diagnostic-v1.schema.json').read_text())
            validate_schema(diagnostic,schema)
    except Exception:
        return MatchingDiagnosticError(err.decode('utf-8','replace')[:1500])
    return MatchingDiagnosticError(message[:8000],diagnostic)


def validate_hoi_settings(settings):
    if not isinstance(settings,dict) or not settings: raise CompanionError('Invalid preserved HOI settings')
    keys=set(settings)
    def point(p): return isinstance(p,list) and len(p)==2 and all(number(v) and abs(v)<=1e9 for v in p)
    if keys=={'ip'} and point(settings['ip']): return
    if keys<={'rc','rd'}:
        if 'rc' in settings and not (settings['rc']=='auto' or point(settings['rc'])): raise CompanionError('Invalid HOI rotation center')
        if 'rd' in settings and settings['rd'] not in ('cw','ccw'): raise CompanionError('Invalid HOI rotation direction')
        return
    if keys<={'tl','tu','al','au'} and all(number(v) and abs(v)<=1e9 for v in settings.values()): return
    raise CompanionError('Unsupported preserved HOI settings')


def decode(data):
    if not isinstance(data, bytes) or not data or len(data) > MAX_FILE:
        raise CompanionError('Matching JSON must be nonempty and no larger than 16 MiB')
    try:
        return json.loads(data, object_pairs_hook=_unique, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (ValueError, TypeError, RecursionError) as exc:
        raise CompanionError('Invalid matching JSON: '+str(exc)) from exc


def validate_outline(value):
    paths = value.get('contours') if isinstance(value, dict) else None
    if not isinstance(paths, list) or not 1 <= len(paths) <= 64:
        raise CompanionError('Matching requires 1...64 closed contours')
    total = 0
    for path in paths:
        if not isinstance(path, dict) or path.get('closed') is not True:
            raise CompanionError('Matching requires closed contours')
        nodes = path.get('nodes')
        if not isinstance(nodes, list) or not 3 <= len(nodes) <= 4096:
            raise CompanionError('Invalid matching node count')
        total += len(nodes)
        for node in nodes:
            if (not isinstance(node, dict) or set(node) != {'x','y','type','smooth'}
                    or not all(number(node[k]) and abs(node[k]) <= 1e9 for k in ('x','y'))
                    or node['type'] not in ('line','curve','offcurve') or type(node['smooth']) is not bool
                    or node['type']=='offcurve' and node['smooth']):
                raise CompanionError('Invalid matching node')
        parts = list(segments(path))
        if len(parts) < 3 or any(end['type']=='curve' and len(controls)!=2 for _,controls,end in parts):
            raise CompanionError('Invalid matching cubic structure')
    if total > 4096:
        raise CompanionError('Matching node resource limit exceeded')
    return value


def parse_master_set(data):
    value = decode(data)
    schema = json.loads((Path(__file__).parents[1]/'master-set-v1.schema.json').read_text())
    validate_schema(value, schema)
    if value['reference']['id']==value['target']['id'] or value['axis']['locations'][0]==value['axis']['locations'][1]:
        raise CompanionError('Matching master identities and locations must differ')
    for role in ('reference','target'):
        validate_outline(value[role]['outline'])
    a,b = [value[role]['outline']['contours'] for role in ('reference','target')]
    if len(a)!=len(b) or len(value['contours'])!=len(a):
        raise CompanionError('Master-set contour correspondence is invalid')
    source = value.get('sourceMasters')
    if not isinstance(source,list) or len(source)!=2:
        raise CompanionError('Master-set source outlines are missing')
    for master in source: validate_outline(master['outline'])
    if any(len(master['outline']['contours'])!=len(a) for master in source): raise CompanionError('Source contour counts differ')
    if [m['id'] for m in source]!=[value[r]['id'] for r in ('reference','target')]: raise CompanionError('Source master identities differ')
    if sorted(r['targetContour'] for r in value['contours'])!=list(range(len(a))): raise CompanionError('Source contour mapping is not a permutation')
    for i,(p,q,report) in enumerate(zip(a,b,value['contours'])):
        if len(p['nodes'])!=len(q['nodes']) or [n['type'] for n in p['nodes']]!=[n['type'] for n in q['nodes']]:
            raise CompanionError('Master-set node correspondence is invalid')
        if report.get('referenceContour')!=i or type(report.get('targetContour')) is not int or not 0<=report['targetContour']<len(source[1]['outline']['contours']):
            raise CompanionError('Invalid source contour mapping')
        for key,master,ci in [('referenceSourceNodes',source[0],i),('targetSourceNodes',source[1],report['targetContour'])]:
            indices=report.get(key)
            count=len(master['outline']['contours'][ci]['nodes'])
            if not isinstance(indices,list) or len(indices)!=len(p['nodes']) or any(v is not None and (type(v) is not int or not 0<=v<count) for v in indices):
                raise CompanionError('Invalid source node mapping')
            used=[v for v in indices if v is not None]
            if len(set(used))!=len(used): raise CompanionError('Duplicate source node mapping')
        if report.get('nodeIDs')!=['c%d.n%d'%(i,j) for j in range(len(p['nodes']))]:
            raise CompanionError('Invalid shared node identities')
    smoothing=value.get('jointSmoothing')
    if bool(value['options'].get('smoothJoins',False)) != (smoothing is not None):
        raise CompanionError('Missing or unexpected joint smoothing verification')
    if smoothing is not None:
        if (smoothing['status'] not in ('smoothed','unchanged') or
                smoothing['proposalDeviation']['upperBound']>value['options']['fitTolerance'] or
                value['interpolation']['sampleCount']!=201 or value['interpolation']['issues'] or
                smoothing['afterMaximumTangencyResidual']!=value['interpolation']['maximumTangencyResidual']):
            raise CompanionError('Joint smoothing did not meet the original fitting limits')
        changes=smoothing['changedHandles']
        keys=[(x['contour'],x['node']) for x in changes]
        if len(set(keys))!=len(keys) or smoothing['proposedHandleChanges']!=len(keys):
            raise CompanionError('Invalid smoothed handle identities')
        for ci,ni in keys:
            if ci>=len(b) or ni>=len(b[ci]['nodes']) or b[ci]['nodes'][ni]['type']!='offcurve':
                raise CompanionError('Smoothing may change only target handles')
    extension=value.get('extensions',{}).get('glyphs4')
    if extension is not None:
        if not isinstance(extension,dict) or extension.get('schemaVersion')!=1 or extension.get('axisTag')!=value['axis']['tag']:
            raise CompanionError('Unsupported Glyphs HOI extension or axis')
        entries=extension.get('entries')
        if not isinstance(entries,list) or len(entries)>4096:
            raise CompanionError('Invalid HOI entries')
        seen=set()
        lower=0 if value['axis']['locations'][0]<value['axis']['locations'][1] else 1
        for entry in entries:
            if not isinstance(entry,dict) or set(entry)!={'master','contour','node','ip'}:
                raise CompanionError('Only intermediate-point HOI entries are supported')
            mi,ci,ni=entry['master'],entry['contour'],entry['node']
            if any(type(v) is not int for v in (mi,ci,ni)) or mi!=lower or not 0<=ci<len(a) or not 0<=ni<len(a[ci]['nodes']):
                raise CompanionError('HOI entry does not identify a lower-span node')
            key=(mi,ci,ni)
            if key in seen: raise CompanionError('Duplicate HOI entries')
            seen.add(key)
            ip=entry['ip']
            if not isinstance(ip,list) or len(ip)!=2 or not all(number(v) and abs(v)<=1e9 for v in ip):
                raise CompanionError('Invalid HOI intermediate point')
        preserved=extension.get('preserved',[])
        if not isinstance(preserved,list) or len(preserved)>8192: raise CompanionError('Invalid preserved HOI entry count')
        for entry in preserved:
            if not isinstance(entry,dict) or set(entry)!={'master','contour','node','settings'}: raise CompanionError('Invalid preserved HOI entry')
            mi,ci,ni=entry['master'],entry['contour'],entry['node']
            if any(type(v) is not int for v in (mi,ci,ni)) or mi not in (0,1) or not 0<=ci<len(a) or not 0<=ni<len(a[ci]['nodes']):
                raise CompanionError('Preserved HOI node is outside the master set')
            key=(mi,ci,ni)
            if key in seen: raise CompanionError('Duplicate preserved HOI entry')
            seen.add(key); validate_hoi_settings(entry['settings'])
    return value


def capabilities(engine, cancel=None):
    import threading
    code,out,err=run_process(engine,['capabilities','--format','json'],b'',cancel or threading.Event(),5,65536)
    if code or err: raise CompanionError('Choose a matching-capable beztrace engine (0.2 development or later)')
    value=decode(out)
    if value.get('schemaVersion')!=1 or value.get('matchSchemaVersion')!=1 or value.get('pathDataVersion')!=2 or value.get('nativeHOI') is not False:
        raise CompanionError('Unsupported matching engine contract')
    return value


def match(engine, request, cancel):
    caps=capabilities(engine,cancel)
    if any(k in request.get('options',{}) for k in ('maxAdditionalOnCurveNodes','maxOnCurveNodes','maxNodes')) and caps.get('nodeBudgetVersion')!=1:
        raise CompanionError('Choose an engine with point-budget support; older engines cannot enforce the point allowance')
    if request.get('mode') and (caps.get('rasterMatchSchemaVersion')!=1 or request['mode'] not in caps.get('matchModes',[])):
        raise CompanionError('Choose an engine with raster master matching support')
    smooth=request.get('options',{}).get('smoothJoins',False)
    if smooth and (caps.get('matchSmoothingVersion')!=1 or caps.get('hybridFittingVersion')!=1):
        raise CompanionError('Choose an engine with verified joint smoothing and hybrid fitting support, or disable Smooth compatible joins')
    data=json.dumps(request,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    if len(data)>MAX_FILE: raise CompanionError('Matching request exceeds 16 MiB')
    code,out,err=run_process(engine,['match','-','--json-errors'],data,cancel,30,MAX_FILE)
    if code:
        raise engine_failure(err)
    if err: raise CompanionError('Unexpected engine diagnostic output')
    result=parse_master_set(out)
    if result['engineVersion']!=caps['engineVersion']:
        raise CompanionError('Engine changed during matching')
    if smooth:
        if (not result['options'].get('smoothJoins',False) or result['unitsPerEm']!=request['unitsPerEm'] or
                result['options']['fitTolerance']!=request['options']['fitTolerance']):
            raise CompanionError('Engine did not preserve the requested smoothing limits')
        if request['options'].get('referencePolicy','fixed')=='fixed' and request.get('reference')!=result['reference']:
            raise CompanionError('Joint smoothing changed the fixed reference')
    if cancel.is_set(): raise Cancelled('Matching cancelled')
    return result


def check_node_budget(result,settings):
    def count(outline): return sum(n['type']!='offcurve' for p in outline['contours'] for n in p['nodes'])
    total=count(result['reference']['outline'])
    nodes=sum(len(p['nodes']) for p in result['reference']['outline']['contours'])
    joint=len(result.get('rasterSources',[]))==2
    original=None if joint else count(result['sourceMasters'][0]['outline'])
    limit=settings['maxOnCurveNodes'] if joint else min(settings['maxOnCurveNodes'],original+settings['maxAdditionalOnCurveNodes'])
    if total>limit or nodes>settings['maxNodes']: raise CompanionError('Result exceeds the point budget: %d on-curves (limit %d), %d total nodes (limit %d). Increase the allowance explicitly and prepare again.'%(total,limit,nodes,settings['maxNodes']))
    report=dict(resultOnCurves=total,allowedAdditional=settings['maxAdditionalOnCurveNodes'],maximumOnCurves=settings['maxOnCurveNodes'],totalNodes=nodes,maximumNodes=settings['maxNodes'])
    if original is not None: report.update(referenceOnCurves=original,addedOnCurves=max(0,total-original))
    return report


def export_bytes(result):
    data=(json.dumps(result,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
    parse_master_set(data)
    return data


def raster_plan(engine,request,cancel):
    caps=capabilities(engine,cancel)
    if caps.get('rasterPlanningVersion')!=1: raise CompanionError('Engine does not provide raster correspondence selectors')
    data=json.dumps(request,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    if len(data)>MAX_FILE: raise CompanionError('Raster planning request exceeds 16 MiB')
    code,out,err=run_process(engine,['match-plan','-','--json-errors'],data,cancel,30,MAX_FILE)
    if code or err: raise CompanionError('Raster correspondence planning failed')
    result=decode(out)
    validate_schema(result,json.loads((Path(__file__).parents[1]/'raster-plan-v1.schema.json').read_text()))
    if result.get('schemaVersion')!=1 or result.get('kind')!='beztrace-raster-plan' or result.get('pathDataVersion')!=2 or result.get('engineVersion')!=caps['engineVersion']:
        raise CompanionError('Unsupported raster planning contract')
    outlines=result.get('outlines'); maps=result.get('sourceNodeIndices')
    if not isinstance(outlines,list) or len(outlines)!=2 or not isinstance(maps,list) or len(maps)!=2:
        raise CompanionError('Invalid raster planning master count')
    for outline,mapping in zip(outlines,maps):
        validate_outline(outline)
        if len(mapping)!=len(outline['contours']): raise CompanionError('Invalid raster planning contour count')
        for path,indices in zip(outline['contours'],mapping):
            if len(indices)!=len(path['nodes']) or any(v is not None and (type(v) is not int or not 0<=v<=131072) for v in indices):
                raise CompanionError('Invalid raster boundary node indices')
    return result


def reference_preflight(engine,request,cancel=None):
    """Read-only reference eligibility report; no target artwork or native writes.

    Supply referenceImage only when it is the rendered reference silhouette at
    the intended affine. A completed report is not fitting/Apply acceptance.
    """
    import threading
    cancel=cancel or threading.Event()
    caps=capabilities(engine,cancel)
    if caps.get('referencePreflightVersion')!=1:
        raise CompanionError('Choose an engine with reference preflight support')
    resources=Path(__file__).parents[1]
    validate_schema(request,json.loads((resources/'match-preflight-request-v1.schema.json').read_text()))
    data=json.dumps(request,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    if len(data)>MAX_FILE: raise CompanionError('Preflight request exceeds 16 MiB')
    code,out,err=run_process(engine,['match-preflight','-','--json-errors'],data,cancel,30,MAX_FILE)
    if code: raise engine_failure(err)
    if err: raise CompanionError('Unexpected preflight diagnostic output')
    result=decode(out)
    validate_schema(result,json.loads((resources/'match-preflight-result-v1.schema.json').read_text()))
    if result['engineVersion']!=caps['engineVersion']: raise CompanionError('Engine changed during preflight')
    if cancel.is_set(): raise Cancelled('Reference preflight cancelled')
    return result
