# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Detached Glyphs CLI qualification; never edits an open document or installs.

glyphs run --app '/Applications/Glyphs 4.app' --plugins '' this-file
BEZTRACE_MATCH_ENGINE selects the separately built development executable.
Only synthetic font objects and workspace .build artifacts are used.
"""
import copy
import json
import os
import sys
import threading
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
sys.path.insert(0,str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'))
import objc
from GlyphsApp import Glyphs,GSFont,GSFontMaster,GSGlyph,GSLayer,GSAnchor,GSInstance,INSTANCETYPEVARIABLE
from beztrace_companion.matching_native import MatchingHost,call
from beztrace_companion.matching import prepare_match,apply_match,export_match
from beztrace_companion.adapter import Target
from beztrace_companion.contract import CompanionError
from beztrace_companion.matching_contract import parse_master_set

ENGINE=os.environ.get('BEZTRACE_MATCH_ENGINE',str(REPO/'.build/release/beztrace'))


class DetachedHost(MatchingHost):
    def target(self,font,glyph_name,layer_id,destination='foreground',sizing=False):
        assert font is self.fixture_font and destination=='foreground'
        glyph=font.glyphs[glyph_name]; layer=glyph.layers[layer_id]
        self.check_editable(glyph,layer)
        return Target(None,font,glyph,layer,layer,destination,self.identity(glyph,layer),self.fingerprint(layer),'Detached matching fixture')
    def contains(self,target):
        return self.same(target.font,self.fixture_font) and self.same(target.glyph.parent,target.font) and self.same(target.owner.parent,target.glyph)
    def redraw(self): pass


def finish(job):
    end=time.monotonic()+90
    while not job.done and time.monotonic()<end:
        job.advance(); time.sleep(.002)
    assert job.done,'Detached preparation timed out'
    return job.plan


def font_fixture():
    font=GSFont(); font.familyName='Beztrace Detached Matching Qualification'
    font.masters=[]
    axis=objc.lookUpClass('GSAxis').alloc().initWithName_tag_('Weight','wght')
    call(font,'setAxes_',[axis])
    for name,value in [('Light',100),('Bold',900)]:
        master=GSFontMaster(); master.name=name; font.masters.append(master)
        call(master,'setAxisInternalValueValue_forId_',value,call(axis,'axisId'))
    return font


def install(host,font,name,outlines):
    glyph=GSGlyph(name); font.glyphs.append(glyph)
    for master,outline in zip(font.masters,outlines):
        layer=glyph.layers[master.id]; layer.width=0
        state=host.rounding_state(layer); host.set_rounding(layer,True)
        try: layer.shapes=host.make_paths(outline['contours'])
        finally: host.set_rounding(layer,state)
        layer.anchors.append(GSAnchor('top',(100,200)))
    manager=glyph.undoManager()
    while manager.groupingLevel(): manager.endUndoGrouping()
    manager.removeAllActions(); manager.setGroupsByEvent_(False)
    return glyph,manager


def run():
    output=REPO/'.build/glyphs-native-matching'; output.mkdir(parents=True,exist_ok=True)
    host=DetachedHost(); font=font_fixture(); host.fixture_font=font
    request=json.loads((REPO/'Tests/Fixtures/matching/v1/shifted-start.json').read_text())
    glyph,manager=install(host,font,'A',[request[role]['outline'] for role in ('reference','target')])
    # Names/user data/attributes survive target reordering and native copies.
    manager.beginUndoGrouping()
    for layer in glyph.layers:
        node=layer.paths[0].nodes[0]; node.name='preserved'; node.userData['fixture']='node'
        call(node,'setAttribute_forKey_','preserved','fixture')
    backup=GSLayer(); backup.name='Unrelated backup'; backup.associatedMasterId=font.masters[0].id
    backup.shapes=host.make_paths(request['reference']['outline']['contours']); glyph.layers.append(backup)
    manager.endUndoGrouping(); manager.removeAllActions()
    backup_before=host.fingerprint(backup)
    before=[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    plan=finish(prepare_match(font,'A',font.masters[0].id,settings=dict(repairHOI=False),engine=ENGINE,_host=host))
    assert before==[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    apply_match(plan); after=[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    assert after!=before and host.fingerprint(backup)==backup_before
    assert all(glyph.layers[m.id].width==0 for m in font.masters)
    manager.undo(); assert before==[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    manager.redo(); assert after==[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    try: apply_match(plan)
    except CompanionError: pass
    else: raise AssertionError('Duplicate Apply succeeded')
    packet=parse_master_set(export_match(plan)); (output/'vector-master-set.json').write_bytes(export_match(plan))
    print('PASS native matching: detached preparation, two-layer Apply, attributes, backup, width, Undo/Redo, duplicate guard, exchange')

    class FaultHost(DetachedHost):
        def install_stage(self,ctx,stage):
            super().install_stage(ctx,stage); raise RuntimeError('Injected two-layer fault')
    faulty=FaultHost(); faulty.fixture_font=font
    failed=finish(prepare_match(font,'A',font.masters[0].id,settings=dict(repairHOI=False),source_mode=3,engine=ENGINE,_host=faulty))
    prior=[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    try: apply_match(failed)
    except CompanionError as exc: assert 'restored' in str(exc),exc
    else: raise AssertionError('Injected failure succeeded')
    assert prior==[host.fingerprint(glyph.layers[m.id]) for m in font.masters]
    print('PASS native rollback and precision restoration')

    native_hoi=False
    if host.hoi_available():
        def outline(points):
            return dict(contours=[dict(closed=True,nodes=[dict(x=x*.08,y=y*.08,type=t,smooth=i==3) for i,(x,y,t) in enumerate(points)])])
        a=outline([(80,40,'line'),(80,90,'offcurve'),(60,200,'offcurve'),(200,200,'curve'),(240,200,'offcurve'),(400,200,'offcurve'),(400,100,'curve')])
        b=outline([(80,40,'line'),(80,90,'offcurve'),(230.717967697,160,'offcurve'),(300,200,'curve'),(473.205080757,300,'offcurve'),(600,380,'offcurve'),(600,100,'curve')])
        repaired,undo=install(host,font,'hoi.fixture',[a,b])
        original=[host.fingerprint(repaired.layers[m.id]) for m in font.masters]
        prepared=finish(prepare_match(font,repaired.name,font.masters[0].id,source_mode=3,engine=ENGINE,_host=host))
        assert prepared.hoi['nativeVerified'],prepared.hoi['unresolved']
        assert prepared.hoi['entries'] and prepared.hoi['sampleCount']==201
        apply_match(prepared); committed=[host.fingerprint(repaired.layers[m.id]) for m in font.masters]
        undo.undo(); assert original==[host.fingerprint(repaired.layers[m.id]) for m in font.masters]
        undo.redo(); assert committed==[host.fingerprint(repaired.layers[m.id]) for m in font.masters]
        (output/'hoi-master-set.json').write_bytes(export_match(prepared)); native_hoi=True
        reviewed=finish(prepare_match(font,repaired.name,font.masters[0].id,source_mode=3,engine=ENGINE,_host=host))
        assert reviewed.hoi['nativeVerified'] and not reviewed.hoi['entries']
        assert reviewed.hoi['preserved']
        print('PASS native ip calibration, 201 locations, movement limit, committed verification and Undo/Redo')
    else: print('PENDING native HOI: evaluator classes are unavailable in this CLI environment')
    original={g.name:[host.fingerprint(g.layers[m.id]) for m in font.masters] for g in font.glyphs}
    variable=GSInstance(type=INSTANCETYPEVARIABLE); variable.name='Matching Test VF'; font.instances.append(variable)
    variable.customParameters['fileName']='BeztraceMatchingFixtureVF'
    source=output/'matching-fixture.glyphs'; font.save(str(source),formatVersion=4)
    assert source.is_file() and source.stat().st_size>0
    reopened=GSFont(str(source))
    maximum_storage_deviation=0.
    def stored_equal(a,b):
        nonlocal maximum_storage_deviation
        if isinstance(a,(int,float)) and isinstance(b,(int,float)) and not isinstance(a,bool) and not isinstance(b,bool):
            distance=abs(a-b); maximum_storage_deviation=max(maximum_storage_deviation,distance)
            return distance<=.001
        if isinstance(a,(tuple,list)) and isinstance(b,(tuple,list)):
            return len(a)==len(b) and all(stored_equal(x,y) for x,y in zip(a,b))
        if isinstance(a,dict) and isinstance(b,dict):
            return a.keys()==b.keys() and all(stored_equal(a[k],b[k]) for k in a)
        return a==b
    for name,states in original.items():
        actual=[host.fingerprint(reopened.glyphs[name].layers[m.id]) for m in reopened.masters]
        if states!=actual:
            (output/'reopen-difference.json').write_text(json.dumps(dict(name=name,before=states,after=actual),indent=2,default=str))
        assert stored_equal(states,actual),name
    if native_hoi:
        reopened_host=DetachedHost(); reopened_host.fixture_font=reopened
        rechecked=finish(prepare_match(reopened,'hoi.fixture',reopened.masters[0].id,source_mode=3,engine=ENGINE,_host=reopened_host))
        assert rechecked.hoi['nativeVerified'],rechecked.hoi['unresolved']
    print('PASS native save/reopen: metadata/flags, measured storage rounding, HOI resampling; maximum numeric deviation',maximum_storage_deviation)
    report=dict(glyphsVersion=str(Glyphs.versionNumber),glyphsBuild=int(Glyphs.buildNumber),python=sys.version,
        engine=ENGINE,vector=True,recovery=True,nativeHOI=native_hoi,visiblePanel=False,saveReopen=True,fontExport=False,
        maximumStorageDeviation=maximum_storage_deviation,storageTolerance=.001,
        moduleSHA256={p.name:__import__('hashlib').sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'Beztrace.glyphsPlugin/Contents/Resources/beztrace_companion').glob('*.py'))})
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__': run()
