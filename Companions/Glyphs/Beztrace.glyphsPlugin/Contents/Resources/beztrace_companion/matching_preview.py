# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Cached preview commands. No native font access or mutation while drawing."""
from .contract import segments, tight_bounds


def commands(paths):
    result=[]
    for path in paths:
        parts=list(segments(path))
        if not parts: continue
        result.append(('M',(parts[0][0]['x'],parts[0][0]['y'])))
        for _,controls,end in parts:
            result.append(('C' if controls else 'L',tuple(v for p in controls+[end] for v in (p['x'],p['y']))))
        result.append(('Z',()))
    return result


def linear(a,b,factor):
    if len(a)!=len(b) or any(len(p['nodes'])!=len(q['nodes']) for p,q in zip(a,b)): return a
    return [dict(closed=True,nodes=[dict(n,x=n['x']+(m['x']-n['x'])*factor,y=n['y']+(m['y']-n['y'])*factor)
                                  for n,m in zip(p['nodes'],q['nodes'])]) for p,q in zip(a,b)]


def payload(context,result=None,hoi=None,factor=0.,diagnostic=None):
    originals=[o['contours'] for o in context['outlines']]
    after=originals if result is None else [result[role]['outline']['contours'] for role in ('reference','target')]
    low=0 if context['axis']['locations'][0]<context['axis']['locations'][1] else 1
    # Raw source nodes have not been paired yet. Interpolating them by index can
    # collapse a valid outline with a different start node. Show the target until
    # a processed result establishes correspondence.
    actual=after[1] if result is None else linear(after[low],after[1-low],factor)
    if hoi is not None and hoi.get('preview'):
        actual=min(hoi['preview'],key=lambda row:abs(row['factor']-factor))['paths']
    all_paths=originals[0]+originals[1]+after[0]+after[1]
    bounds=tight_bounds(all_paths) if all_paths else (0,0,1000,1000)
    links=[]
    if result is not None:
        for a,b in zip(*after):
            for n,m in zip(a['nodes'],b['nodes']):
                if n['type']!='offcurve': links.append(((n['x'],n['y']),(m['x'],m['y'])))

    markers=[]; highlights=[]
    # Highlight input source segments only. Fitted failure geometry is not a result
    # and must not be reconstructed from the source node IDs or shown as accepted.
    if diagnostic and diagnostic.get('stage') in ('input','reference-preflight'):
        role=diagnostic.get('role'); index={'reference':0,'target':1}.get(role)
        if index is not None:
            for location in diagnostic.get('locations',[]):
                ci,si=location['contour'],location['segment']
                if ci>=len(originals[index]): continue
                parts=list(segments(originals[index][ci]))
                if si>=len(parts): continue
                start,controls,end=parts[si]
                highlights += [('M',(start['x'],start['y'])),
                    ('C' if controls else 'L',tuple(v for p in controls+[end] for v in (p['x'],p['y'])))]
            if diagnostic.get('coordinates'):
                point=tuple(diagnostic['coordinates']); markers.append(point)
                bounds=(min(bounds[0],point[0]),min(bounds[1],point[1]),max(bounds[2],point[0]),max(bounds[3],point[1]))
    return dict(bounds=tuple(bounds),before=[commands(p) for p in originals],masters=[commands(p) for p in after],after=commands(actual),links=links,processed=result is not None,
                diagnosticMarkers=markers,diagnosticHighlights=highlights)
