# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Version 1 agent API: prepare and apply native image placements, never paths."""
import threading
from dataclasses import dataclass
from pathlib import Path
from .contract import CompanionError
from .engine import DEFAULT_ENGINE, trace, Cancelled
from .placement import resolve
from .canvas import fitted_transform
from .adapter import revalidate, apply_image
from . import image_io

API_VERSION=1


@dataclass(frozen=True)
class ImportRequest:
    path: str
    glyph: str
    layer_id: str
    preset: str='Auto'
    height: float=700.0
    bottom: float=0.0
    horizontal: float=0.0
    destination: str='foreground'
    replace: bool=False


@dataclass(frozen=True)
class PreparedImport:
    request: ImportRequest
    target: object
    image: object
    snapshot: object
    source_hash: str
    transform: tuple
    original_image_state: object


class ImportPlan:
    def __init__(self, items, cancel):
        self.items=tuple(items)
        self.cancel=cancel
        self.consumed=False


class Preparation:
    def __init__(self):
        self._cancel=threading.Event(); self._done=threading.Event()
        self._plan=None; self.error=None

    def cancel(self): self._cancel.set()
    @property
    def done(self): return self._done.is_set()
    @property
    def plan(self):
        if not self.done: raise CompanionError('Image preparation is still running')
        if self._cancel.is_set(): raise Cancelled('Image preparation cancelled')
        if self.error: raise self.error
        return self._plan


def prepare_imports(font, entries, *, engine=DEFAULT_ENGINE, _host=None):
    """Call on main thread; poll the returned Preparation.done without blocking.

    No font writes. A successful job.plan can be applied once with apply_imports.
    Cancellation remains effective after preparation, until application starts.
    _host is a test seam, not versioned client API.
    """
    from .native import GlyphsHost
    host=_host or GlyphsHost(); host.assert_main()
    requests=tuple(entries)
    if not requests: raise CompanionError('Provide at least one image import')
    staged=[]; seen=set()
    for request in requests:
        if not isinstance(request,ImportRequest): raise CompanionError('Entries must be ImportRequest objects')
        if type(request.replace) is not bool: raise CompanionError('replace must be a boolean')
        target=host.target(font,request.glyph,request.layer_id,request.destination,sizing=True)
        key=(target.identity,request.destination)
        if key in seen: raise CompanionError('A batch must not place multiple images on the same layer')
        seen.add(key)
        if target.layer.backgroundImage is not None and not request.replace:
            raise CompanionError('Existing canvas image on '+target.label+'; request replacement explicitly')
        fit=resolve(request.preset,target.classification,target.metrics,request.height,request.bottom)
        path=str(Path(request.path).expanduser().resolve())
        image=host.new_image(path)
        snap=image_io.snapshot(image)
        staged.append((request,target,image,snap,fit,host.image_state(image)))
    job=Preparation()
    def worker():
        try:
            items=[]
            for request,target,image,snap,fit,state in staged:
                if job._cancel.is_set(): raise Cancelled('Image preparation cancelled')
                data,source_hash=image_io.prepare(snap,job._cancel)
                result=trace(engine,data,{},job._cancel)
                transform=fitted_transform(result,snap.geometry.size,fit,request.horizontal)
                items.append(PreparedImport(request,target,image,snap,source_hash,transform,state))
            if job._cancel.is_set(): raise Cancelled('Image preparation cancelled')
            job._plan=ImportPlan(items,job._cancel)
        except Exception as exc: job.error=exc
        finally:
            job._done.set()
    threading.Thread(target=worker,name='Beztrace image placement',daemon=True).start()
    return job


def apply_imports(plan, *, _host=None):
    """Call on main thread. Preflight all items, then apply with per-item undo.

    Stops on first application failure and reports completed/failed/not-applied
    entries. The failed item uses verified image recovery. Never saves a font.
    """
    from .native import GlyphsHost
    host=_host or GlyphsHost(); host.assert_main()
    if not isinstance(plan,ImportPlan) or plan.consumed:
        raise CompanionError('Use a fresh prepared import plan')
    if plan.cancel.is_set(): raise Cancelled('Image preparation cancelled')
    for item in plan.items:
        revalidate(host,item.target)
        if (image_io.file_state(item.snapshot.path)!=item.snapshot.file_state
                or image_io.digest(image_io.read_source(item.snapshot.path))!=item.source_hash):
            raise CompanionError('An import source changed; prepare the batch again')
        if host.image_state(item.image)!=item.original_image_state:
            raise CompanionError('A prepared image was modified; prepare the batch again')
    plan.consumed=True
    results=[]; stopped=False
    for item in plan.items:
        record=dict(glyph=item.request.glyph,layer_id=item.request.layer_id,destination=item.request.destination)
        if stopped:
            results.append(dict(record,status='not-applied')); continue
        if plan.cancel.is_set():
            results.append(dict(record,status='cancelled')); stopped=True; continue
        try:
            item.image.transform=item.transform
            apply_image(host,item.target,item.image,item.request.replace)
            results.append(dict(record,status='applied',transform=item.transform))
        except Exception as exc:
            from .adapter import RecoveryError
            results.append(dict(record,status='recovery-failed' if isinstance(exc,RecoveryError) else 'failed',error=str(exc)))
            stopped=True
    return dict(api_version=API_VERSION,completed=sum(r['status']=='applied' for r in results),items=results)
