# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Prepare/preview/apply matching; no native access from a worker thread."""
import copy
import threading
from dataclasses import dataclass
from .contract import CompanionError, number
from .engine import default_engine, Cancelled
from .adapter import RecoveryError
from .matching_hints import HintMappingError
from . import matching_contract as contract

MATCH_API_VERSION = contract.MATCH_API_VERSION
DEFAULT_SETTINGS=dict(referencePolicy='fixed',fitTolerance=1.,repairHOI=True,kinkThreshold=1.,maxShapeMovement=5.,
                      contourPairs=[],startNodes=[],maxAdditionalOnCurveNodes=0,maxOnCurveNodes=64,maxNodes=64,smoothJoins=False)


def options(value):
    if value is not None and set(value)-set(DEFAULT_SETTINGS): raise CompanionError('Unknown matching setting')
    result=copy.deepcopy(DEFAULT_SETTINGS); result.update(value or {})
    if result['referencePolicy'] not in ('fixed','shared-subdivision') or any(type(result[k]) is not bool for k in ('repairHOI','smoothJoins')):
        raise CompanionError('Invalid reference policy or repair setting')
    for key in ('fitTolerance','kinkThreshold','maxShapeMovement'):
        if not number(result[key]) or not 0<result[key]<=100: raise CompanionError('Invalid '+key)
    for key in ('contourPairs','startNodes'):
        if not isinstance(result[key],list) or any(type(x) is not int for x in result[key]): raise CompanionError('Invalid '+key)
    for key,low in (('maxAdditionalOnCurveNodes',0),('maxOnCurveNodes',3)):
        if type(result[key]) is not int or not low<=result[key]<=1024: raise CompanionError('Invalid '+key)
    if type(result['maxNodes']) is not int or not 3<=result['maxNodes']<=4096: raise CompanionError('Invalid maxNodes')
    return result


@dataclass
class MatchPlan:
    context: dict
    result: dict
    stage: object
    hoi: object
    settings: dict
    cancel_event: object
    host: object
    consumed: bool=False
    poisoned: bool=False
    apply_error: str=None


class MatchingPreparation:
    def __init__(self,host,ctx,settings):
        self.host=host; self.context=ctx; self.settings=settings
        self._cancel=threading.Event(); self._ready=threading.Event(); self._done=False
        self.error=None; self.result=None; self.progress='Matching outlines'; self._native=None; self._plan=None
        self.imported_entries=[]
        self.imported_existing=[]
        self.planning=None
    def cancel(self): self._cancel.set()
    @property
    def done(self): return self._done
    @property
    def plan(self):
        if not self.done: raise CompanionError('Call advance() on the main thread until preparation finishes')
        if self.error: raise self.error
        if self._cancel.is_set(): raise Cancelled('Matching cancelled')
        return self._plan
    def advance(self):
        self.host.assert_main()
        if self._done: return
        if self._cancel.is_set(): self.error=Cancelled('Matching cancelled'); self._done=True; return
        if not self._ready.is_set(): return
        if self.error: self._done=True; return
        try:
            self.host.revalidate_match(self.context)
            if self._native is None:
                stage=self.host.stage(self.context,self.result)
                self._plan=MatchPlan(self.context,self.result,stage,None,self.settings,self._cancel,self.host)
                if not self.settings['repairHOI']:
                    self.result.pop('extensions',None)
                    preserved=getattr(self.host,'existing_hoi',lambda stage:[])(stage)
                    if preserved:
                        self.result['extensions']={'glyphs4':dict(schemaVersion=1,axisTag=self.context['axis']['tag'],
                            entries=[],preserved=preserved,verification=dict(sampledOnly=True,nativeVerified=False))}
                    self._done=True; self.progress='Ready to review'; return
                if not self.host.hoi_available():
                    raise CompanionError('Automatic HOI is unavailable on this Glyphs build. Disable repair to prepare matching only.')
                from .hoi import prepare
                self._native=prepare(stage,self.host,self.settings,self._cancel,self.imported_entries,
                                     imported_existing=self.imported_existing,
                                     evaluator=getattr(self.host,'hoi_evaluator',None))
            try:
                update=next(self._native); self.progress=update['stage']+' (%d%%)'%round(update['factor']*100)
            except StopIteration as final:
                report=final.value; self._plan.stage=report['stage']; self._plan.hoi=report
                self.result['extensions']={'glyphs4':dict(schemaVersion=1,axisTag=self.context['axis']['tag'],
                    entries=report['entries'],preserved=report['preserved'],verification={k:report[k] for k in ('sampledOnly','nativeVerified','sampleCount','maximumDeviation','rmsDeviation','unresolved','reports','joinChecks')})}
                self._done=True; self.progress='Ready to review' if not report['unresolved'] else 'HOI needs review; Apply is blocked'
        except Exception as exc:
            self.error=exc; self._done=True


def prepare_match(font,glyph,reference_id,*,settings=None,engine=None,imported=None,confirm_axis=False,source_mode=0,
                  raster_options=None,_host=None):
    from .matching_native import MatchingHost
    host=_host or MatchingHost(); host.assert_main()
    settings=options(settings); ctx=host.context(font,glyph,reference_id)
    ctx['match_review_only']=source_mode==3 and imported is None
    if type(source_mode) is not int or source_mode not in range(4): raise CompanionError('Invalid matching source mode')
    job=MatchingPreparation(host,ctx,settings)
    imported_result=None; sources=None
    if imported is not None:
        imported_result=contract.parse_master_set(imported)
        settings['smoothJoins']=bool(imported_result['options'].get('smoothJoins',False))
        contract.check_node_budget(imported_result,settings)
        if not confirm_axis or imported_result['axis']['tag']!=ctx['axis']['tag']:
            raise CompanionError('Explicitly confirm mapping the file to the current axis')
        if imported_result['unitsPerEm']!=ctx['unitsPerEm']:
            raise CompanionError('File and font UPM must match; automatic rescaling is not supported')
        a=imported_result['axis']['locations']; b=ctx['axis']['locations']
        if (a[0]<a[1])!=(b[0]<b[1]): raise CompanionError('Choose the reference master that preserves the file span direction')
        if imported_result.get('rasterSources'):
            # Validate the exact reviewed endpoints without re-running extraction
            # or trusting native claims. Source mappings/evidence stay in the file.
            request=dict(schemaVersion=1,unitsPerEm=ctx['unitsPerEm'],axis=ctx['axis'],
                reference=imported_result['reference'],target=imported_result['target'],
                options=dict(referencePolicy='fixed',fitTolerance=imported_result['options']['fitTolerance'],
                             preserveStructure=True,maxAdditionalOnCurveNodes=settings['maxAdditionalOnCurveNodes'],maxOnCurveNodes=settings['maxOnCurveNodes'],maxNodes=settings['maxNodes']))
            if imported_result['options'].get('smoothJoins'):
                # Idempotent review of the exact imported endpoints at 201
                # positions. The historical raster certificate is retained,
                # not replaced with a zero distance to these fitted endpoints.
                request['options']['smoothJoins']=True
        else:
            request=dict(schemaVersion=1,unitsPerEm=ctx['unitsPerEm'],axis=ctx['axis'],
                         reference=imported_result['sourceMasters'][0],target=imported_result['sourceMasters'][1],
                         options=imported_result['options'])
            request['options']=dict(request['options'],maxAdditionalOnCurveNodes=settings['maxAdditionalOnCurveNodes'],maxOnCurveNodes=settings['maxOnCurveNodes'],maxNodes=settings['maxNodes'])
        if settings['repairHOI']:
            job.imported_entries=copy.deepcopy(imported_result.get('extensions',{}).get('glyphs4',{}).get('entries',[]))
            job.imported_existing=copy.deepcopy(imported_result.get('extensions',{}).get('glyphs4',{}).get('preserved',[]))
    else:
        if source_mode in (0,3) and not all(o['contours'] for o in ctx['outlines']):
            raise CompanionError('Both masters need outlines; select a raster mode or Import for empty layers')
        if source_mode==1 and not ctx['outlines'][0]['contours']: raise CompanionError('Trace to reference needs a reference outline')
        request=dict(schemaVersion=1,unitsPerEm=ctx['unitsPerEm'],axis=ctx['axis'],
            reference=dict(id=str(ctx['targets'][0].owner.layerId),outline=ctx['outlines'][0]),
            target=dict(id=str(ctx['targets'][1].owner.layerId),outline=ctx['outlines'][1]),
            options=dict(referencePolicy=settings['referencePolicy'],fitTolerance=settings['fitTolerance']*ctx['unitsPerEm']/1000,
                         contourPairs=settings['contourPairs'],startNodes=settings['startNodes'],
                         maxAdditionalOnCurveNodes=settings['maxAdditionalOnCurveNodes'],maxOnCurveNodes=settings['maxOnCurveNodes'],maxNodes=settings['maxNodes']))
        if source_mode==3:
            request['options'].update(preserveStructure=True,contourPairs=[],startNodes=[],referencePolicy='fixed')
        elif source_mode in (1,2):
            if source_mode==2 and settings['referencePolicy']!='shared-subdivision':
                raise CompanionError('Trace both images requires explicitly selected shared subdivision')
            from .matching_raster import capture
            sources=capture(ctx,source_mode)
            request['mode']='trace-to-reference' if source_mode==1 else 'trace-both'
            del request['target']
            if source_mode==2:
                del request['reference']
            ro=dict(threshold=None,invert=False,minimumContourArea=100.,smoothing=1.,cornerThresholdDegrees=12.)
            if raster_options:
                if set(raster_options)-set(ro): raise CompanionError('Unknown raster matching setting')
                ro.update(raster_options)
            request['rasterOptions']=ro
        if settings['smoothJoins']: request['options']['smoothJoins']=True
    executable=engine or default_engine()
    def worker():
        try:
            if sources is not None:
                from .matching_raster import prepare_sources
                request['images']=prepare_sources(ctx,sources,job._cancel)
            result=contract.match(executable,request,job._cancel)
            if imported_result is not None:
                for role in ('reference','target'):
                    if result[role]['outline']!=imported_result[role]['outline']:
                        raise CompanionError('Imported geometry does not reproduce its source/policy contract')
                # Claim-free native extension will be recreated after sampling.
                if imported_result.get('rasterSources'):
                    checked=copy.deepcopy(imported_result); checked.pop('extensions',None)
                    checked.update(axis=ctx['axis'],interpolation=result['interpolation'],engineVersion=result['engineVersion'])
                    result=checked
                result['options'].update({k:settings[k] for k in ('maxAdditionalOnCurveNodes','maxOnCurveNodes','maxNodes')})
            if not ctx.get('match_review_only'): result['nodeBudget']=contract.check_node_budget(result,settings)
            job.result=result
        except Exception as exc:
            job.error=exc
            if sources is not None and not job._cancel.is_set() and 'images' in request:
                try: job.planning=contract.raster_plan(executable,request,job._cancel)
                except Exception: pass  # Retain the original actionable matching error.
        finally: job._ready.set()
    threading.Thread(target=worker,name='Beztrace master matching',daemon=True).start()
    return job


def apply_match(plan):
    if not isinstance(plan,MatchPlan) or plan.consumed or plan.poisoned:
        raise CompanionError('Use a fresh reviewed matching plan')
    host=plan.host; host.assert_main(); host.revalidate_match(plan.context)
    if not plan.context.get('match_review_only'): contract.check_node_budget(plan.result,plan.settings)
    if plan.cancel_event.is_set(): raise Cancelled('Matching cancelled')
    if plan.settings['repairHOI'] and (plan.hoi is None or not plan.hoi['nativeVerified'] or plan.hoi['unresolved']):
        raise CompanionError('HOI is unresolved; disable repair and prepare again to apply matching only')
    try:
        prepare_stage=getattr(host,'prepare_apply_stage',None)
        application_stage=prepare_stage(plan.context,plan.stage,plan.result) if prepare_stage else plan.stage
    except HintMappingError as exc:
        plan.apply_error=str(exc)
        raise
    targets=plan.context['targets']; snapshots=[host.snapshot(t.layer) for t in targets]
    fingerprints=[host.fingerprint(t.layer) for t in targets]
    rounding=[host.rounding_state(t.layer) for t in targets]
    plan.consumed=True; begun=False
    try:
        host.begin_undo(plan.context['glyph']); begun=True
        try:
            for t in targets: host.set_rounding(t.layer,True)
            host.install_stage(plan.context,application_stage)
            for t,value in zip(targets,rounding): host.set_rounding(t.layer,value)
            host.verify_stage(plan.context,application_stage,snapshots)
            if plan.hoi is not None:
                committed=dict(font=plan.context['font'],layers=[t.layer for t in targets],context=plan.context)
                verifier=getattr(host,'verify_hoi',None)
                if verifier is None:
                    from .hoi import verify_committed
                    verifier=lambda stage,report:verify_committed(stage,host,report,plan.settings,plan.cancel_event)
                verifier(committed,plan.hoi)
        except Exception as original:
            failures=[]
            for t,snapshot,state,prior in zip(targets,snapshots,rounding,fingerprints):
                try:
                    host.set_rounding(t.layer,True); host.restore(t.layer,snapshot); host.set_rounding(t.layer,state)
                    if host.fingerprint(t.layer)!=prior: raise RuntimeError('Layer recovery differs from snapshot')
                except Exception as exc: failures.append(str(exc))
            if failures:
                plan.poisoned=True
                if hasattr(host,'block_writes'): host.block_writes()
                raise RecoveryError('Two-master recovery failed; stop editing this target: '+'; '.join(failures)) from original
            raise CompanionError('Apply failed; both master layers were restored: '+str(original)) from original
    finally:
        failures=[]
        for t,state in zip(targets,rounding):
            try:
                host.set_rounding(t.layer,state)
                if host.rounding_state(t.layer)!=state: raise RuntimeError('Precision state restoration failed')
            except Exception as exc: failures.append(str(exc))
        if begun:
            try: host.end_undo(plan.context['glyph'])
            except Exception as exc: failures.append(str(exc))
        if failures:
            plan.poisoned=True
            if hasattr(host,'block_writes'): host.block_writes()
            raise RecoveryError('Matching transaction cleanup failed: '+'; '.join(failures))
    warning=None
    try: host.redraw()
    except Exception: warning='Applied; refresh Glyphs to display the result'
    return dict(api_version=MATCH_API_VERSION,status='applied',masters=2,native_hoi=bool(plan.hoi),warning=warning)


def export_match(plan):
    if not isinstance(plan,MatchPlan) or plan.poisoned: raise CompanionError('Prepare and review a matching result first')
    plan.host.assert_main()
    if plan.cancel_event.is_set(): raise Cancelled('Matching cancelled')
    if not plan.consumed: plan.host.revalidate_match(plan.context)
    if plan.hoi is not None and plan.hoi['unresolved']: raise CompanionError('Resolve HOI before exporting')
    return contract.export_bytes(plan.result)
