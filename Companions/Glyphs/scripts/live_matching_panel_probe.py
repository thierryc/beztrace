# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Run through an authorized native script workflow on a new pathless QA font.

No Save, export, installation, font file write or document close. The workspace
panel is loaded under a distinct package name to preserve the installed plugin.
Actions: setup, show, inspect, prepare, cancel, invalidate, selection_failure,
close_panel. Every action verifies the exact disposable font before proceeding.
"""
import copy
import hashlib
import importlib
import importlib.util
import json
from pathlib import Path
import sys
import objc
from GlyphsApp import GSFontMaster,GSGlyph,GSAnchor

PACKAGE='beztrace_matching_live_20261011'
expected=params['family']
assert str(font.familyName)==expected,'Wrong document family'
assert not font.filepath and font.parent is not None,'QA font must be open and pathless'
assert objc.pyobjc_id(Glyphs.font)==objc.pyobjc_id(font),'QA font must be current'
action=params['action']

if action=='setup':
    assert PACKAGE not in sys.modules,'QA module already exists; inspect rather than replay setup'
    assert len(font.masters)==1 and not len(font.glyphs),'QA setup requires a fresh empty font'
    resources=Path(params['resources']).resolve()
    spec=importlib.util.spec_from_file_location(PACKAGE,resources/'beztrace_companion/__init__.py',
        submodule_search_locations=[str(resources/'beztrace_companion')])
    package=importlib.util.module_from_spec(spec); sys.modules[PACKAGE]=package; spec.loader.exec_module(package)
    native=importlib.import_module(PACKAGE+'.matching_native')
    host=native.MatchingHost()
    axis=objc.lookUpClass('GSAxis').alloc().initWithName_tag_('Weight','wght')
    native.call(font,'setAxes_',[axis])
    font.masters[0].name='Light'
    font.masters.append(GSFontMaster()); font.masters[1].name='Bold'
    for master,value in zip(font.masters,(100,900)):
        native.call(master,'setAxisInternalValueValue_forId_',value,native.call(axis,'axisId'))
    def path(points):
        return dict(closed=True,nodes=[dict(x=x,y=y,type='line',smooth=False) for x,y in points])
    box=path([(0,0),(100,0),(100,200),(0,200)])
    shifted=path([(100,200),(0,200),(0,0),(100,0)])
    crossing=path([(20,20),(120,220),(20,220),(100,20)])
    cubic=copy.deepcopy(crossing); cubic['nodes']=[]
    for i,node in enumerate(crossing['nodes']):
        if i in (1,3):
            start=crossing['nodes'][i-1]
            for factor in (1/3,2/3):
                cubic['nodes'].append(dict(x=start['x']+(node['x']-start['x'])*factor,
                    y=start['y']+(node['y']-start['y'])*factor,type='offcurve',smooth=False))
        cubic['nodes'].append(dict(node,type='curve' if i in (1,3) else 'line'))
    cases={'qa.valid':[box,shifted],'qa.reference.line':[crossing,box],
        'qa.target.line':[box,crossing],'qa.reference.cubic':[cubic,box],
        'qa.target.cubic':[box,cubic]}
    for name,shapes in cases.items():
        glyph=GSGlyph(name); font.glyphs.append(glyph)
        for master,shape in zip(font.masters,shapes):
            layer=glyph.layers[master.id]; layer.width=300
            prior=host.rounding_state(layer)
            try:
                host.set_rounding(layer,True); layer.shapes=host.make_paths([shape])
            finally: host.set_rounding(layer,prior)
            layer.anchors.append(GSAnchor('top',(50,240)))
    package._qa=dict(font=font,host=host,controller=None,case=None,resources=str(resources),
        engine=str(Path(params['engine']).resolve()),baseline={name:[host.fingerprint(font.glyphs[name].layers[m.id])
            for m in font.masters] for name in cases},checks=[])
    print(json.dumps(dict(status='setup',family=expected,masters=[str(m.id) for m in font.masters],
        glyphs=list(cases),fontPath=font.filepath,glyphsVersion=str(Glyphs.versionNumber),
        glyphsBuild=int(Glyphs.buildNumber),python=sys.version,hoiAvailable=host.hoi_available())))
else:
    package=sys.modules[PACKAGE]; state=package._qa; host=state['host']
    assert host.same(state['font'],font),'Disposable native font identity changed'
    def preserved():
        assert not font.filepath,'QA font acquired a path'
        for name,expected_shapes in state['baseline'].items():
            assert [host.fingerprint(font.glyphs[name].layers[m.id]) for m in font.masters]==expected_shapes, 'QA source changed: '+name
    preserved()
    if action=='show':
        module=importlib.import_module(PACKAGE+'.matching_ui')
        if state['controller'] is None or state['controller'].closed:
            state['controller']=module.MatchingWindowController.alloc().init()
        controller=state['controller']; controller.engine=state['engine']
        assert controller.host.same(controller.host.app.font,font),'Panel current font mismatch'
        if params.get('endpoint'): controller.slider.setDoubleValue_(0)
        controller.useSelection_(None)
        assert controller.ctx is not None,controller.details
        assert controller.host.same(controller.ctx['font'],font),'Panel bound another font'
        assert str(controller.ctx['targets'][1].owner.layerId)==str(controller.host.current_selection()[3].layerId), 'Current master was not selected as target'
        state['case']=str(controller.ctx['glyph'].name)
        controller.showWindow_(None); controller.window().makeKeyAndOrderFront_(None)
    elif action=='prepare':
        controller=state['controller']
        assert controller.host.same(controller.ctx['font'],font),'Panel bound another font'
        controller.prepare_(None)
    elif action=='cancel': state['controller'].cancel_(None)
    elif action=='invalidate':
        controller=state['controller']; controller.settingsChanged_(None)
        assert controller.diagnostic is None and controller.plan is None
        assert not controller.preview.cache['diagnosticHighlights']
        assert not controller.preview.cache['diagnosticMarkers']
        assert not controller.apply_button.isEnabled()
        state['checks'].append('invalidation clears diagnostics and disables Apply')
    elif action=='selection_failure':
        controller=state['controller']; controller.useSelection_(None)
        assert controller.ctx is None and not controller.apply_button.isEnabled()
        assert not controller.prepare_button.isEnabled()
        assert 'exactly one glyph' in str(controller.status.stringValue())
        state['checks'].append('empty selection rejected; Apply/Prepare disabled')
    elif action=='close_panel':
        controller=state['controller']; controller.window().close()
        assert controller.closed and controller.timer is None and not controller.window().isVisible()
        state['checks'].append('native panel closes and timer is removed')
    elif action!='inspect': raise AssertionError('Unknown action')
    controller=state['controller']
    if not controller.closed: controller.poll_(None)
    if controller.ctx is not None: state['case']=str(controller.ctx['glyph'].name)
    preserved()
    report=dict(action=action,case=state['case'],path=font.filepath,sourcePreserved=True,
        nativeHost=type(controller.host).__module__,visible=bool(controller.window().isVisible()),
        closed=controller.closed,busy=controller.job is not None,plan=controller.plan is not None,
        prepareEnabled=bool(controller.prepare_button.isEnabled()),applyEnabled=bool(controller.apply_button.isEnabled()),
        primaryAction=controller.primary_action,
        referenceMasterID=str(controller.ctx['targets'][0].owner.layerId) if controller.ctx else None,
        targetMasterID=str(controller.ctx['targets'][1].owner.layerId) if controller.ctx else None,
        exportEnabled=bool(controller.export_button.isEnabled()),status=str(controller.status.stringValue()),
        diagnostic=controller.diagnostic,checks=state['checks'],
        highlightCommands=controller.preview.cache.get('diagnosticHighlights',[]) if controller.preview.cache else [],
        markers=controller.preview.cache.get('diagnosticMarkers',[]) if controller.preview.cache else [])
    if params.get('expect') and not report['busy']:
        expectation=params['expect']
        if expectation=='valid':
            assert report['plan'] and report['applyEnabled'],controller.details
            assert not report['diagnostic'] and not report['highlightCommands']
        elif expectation=='budget':
            assert not report['plan'] and not report['applyEnabled'] and not report['exportEnabled'],controller.details
            assert 'point budget exceeded' in report['status'].lower(),controller.details
        else:
            role=expectation.split('.')[0]; kind=expectation.split('.')[1]
            diagnostic=report['diagnostic']; assert diagnostic is not None,controller.details
            assert diagnostic['stage']=='input' and diagnostic['role']==role and diagnostic['existedBeforeFitting']
            assert diagnostic['masterID']==report['referenceMasterID' if role=='reference' else 'targetMasterID']
            assert [(p['segment'],p['startNode'],p['endNode']) for p in diagnostic['locations']]==(
                [(0,0,1),(2,2,3)] if kind=='line' else [(0,0,3),(2,4,7)])
            assert len(report['highlightCommands'])==4 and len(report['markers'])==1
            assert abs(report['markers'][0][0]-(20+400/9))<1e-7
            assert abs(report['markers'][0][1]-(20+800/9))<1e-7
            assert not report['plan'] and not report['applyEnabled'] and not report['exportEnabled']
            assert '"locations"' in controller.details and '"startNode"' in controller.details
        state['checks'].append(expectation+' verified with unchanged native sources')
    if params.get('identity'):
        module=importlib.import_module(PACKAGE+'.matching_ui')
        report['loadedModule']=module.__file__
        report['moduleSHA256']={Path(m.__file__).name:hashlib.sha256(Path(m.__file__).read_bytes()).hexdigest()
            for name,m in sys.modules.items() if name.startswith(PACKAGE+'.matching') and getattr(m,'__file__',None)}
        report['engineSHA256']=hashlib.sha256(Path(state['engine']).read_bytes()).hexdigest()
        report['glyphsBuild']=int(Glyphs.buildNumber); report['python']=sys.version
    print(json.dumps(report,default=str))
