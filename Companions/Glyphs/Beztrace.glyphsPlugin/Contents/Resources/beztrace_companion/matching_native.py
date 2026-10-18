# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Two-master native boundary. Imported only inside Glyphs; main thread only."""
import copy
from .native import GlyphsHost, _native_items, _value
from .contract import CompanionError
from .adapter import revalidate


def call(obj,name,*args): return getattr(obj.pyobjc_instanceMethods,name)(*args)


class MatchingHost(GlyphsHost):
    writes_blocked=False
    def __init__(self):
        super().__init__()
        self.native_types={int(call(self.Node((0.,0.),kind),'type')) for kind in self.types.values()}
    def check_replace(self,layer):
        if any(bool(call(p,'isLocked')) for p in layer.paths):
            raise CompanionError('Unlock existing paths before matching')
        if any(bool(call(n,'isLocked')) for p in layer.paths for n in p.nodes):
            raise CompanionError('Unlock existing nodes before matching')

    def shape_state(self,shape):
        state=super().shape_state(shape)
        if isinstance(shape,self.Path):
            flags=tuple((int(call(n,'type')),int(call(n,'connection')),int(call(n,'orientation')),bool(call(n,'isLocked'))) for n in shape.nodes)
            return state+(bool(call(shape,'isLocked')),flags)
        return state

    def preserved_state(self,layer):
        from .matching_hints import metadata
        from .native import _properties
        state=super().preserved_state(layer)
        hints=tuple((metadata(h),_properties(h,['origin','target','other1','other2','position','width']))
                    for h in _native_items(layer.hints))
        return state[:4]+(hints,)+state[5:]
    def context(self,font,glyph_name,reference_id):
        self.assert_main()
        if self.writes_blocked: raise CompanionError('Matching writes are disabled after a recovery failure; restart the session')
        axes=list(font.axes); masters=list(font.masters)
        if len(axes)!=1 or len(masters)!=2:
            raise CompanionError('Match Masters requires exactly two masters and one axis')
        glyph=font.glyphs[glyph_name]
        if glyph is None: raise CompanionError('Select one existing glyph')
        if reference_id not in [str(m.id) for m in masters]:
            raise CompanionError('Choose an ordinary master as the reference')
        masters.sort(key=lambda m: str(m.id)!=reference_id)
        axis=axes[0]; tag=str(call(axis,'axisTag')); axis_id=call(axis,'axisId')
        locations=[float(call(m,'axisInternalValueValueForId_',axis_id)) for m in masters]
        import math
        if not tag or not all(math.isfinite(x) for x in locations) or locations[0]==locations[1]:
            raise CompanionError('Master axis locations must be finite and different')
        for layer in glyph.layers:
            if getattr(layer,'isSpecialLayer',False):
                raise CompanionError('Intermediate and alternate interpolation layers are not supported')
        targets=[self.target(font,glyph_name,str(m.id)) for m in masters]
        for target in targets:
            self.check_replace(target.layer)
            if len(target.layer.shapes)!=len(target.layer.paths):
                raise CompanionError('Components and other shape types are not supported')
            for path in target.layer.paths:
                if not path.closed or any(n.type not in self.types.values() or int(call(n,'type')) not in self.native_types for n in path.nodes):
                    raise CompanionError('Only closed line/cubic paths are supported')
        return dict(font=font,glyph=glyph,targets=targets,axis=dict(tag=tag,locations=locations),
                    axis_id=str(axis_id),unitsPerEm=float(font.upm),reference_id=reference_id,
                    axis_fingerprint=self.axis_state(font),
                    glyph_fingerprint=self.glyph_state(glyph),
                    outlines=[dict(contours=[self.path_data(p) for p in t.layer.paths]) for t in targets])

    @staticmethod
    def glyph_state(glyph):
        return tuple((key,_value(getattr(glyph,key,None))) for key in
                     ('name','unicode','unicodes','category','subCategory','script','userData','locked'))

    def axis_state(self,font):
        axes=list(font.axes)
        def parameters(owner):
            return tuple((str(p.name),_value(p.value),_value(getattr(p,'disabled',None))) for p in _native_items(owner.customParameters))
        return (float(font.upm),tuple((str(call(a,'axisId')),str(call(a,'axisTag')),str(a.name)) for a in axes),
                tuple((str(m.id),str(m.name),_value(m.userData),parameters(m),
                       tuple(float(call(m,'axisInternalValueValueForId_',call(a,'axisId'))) for a in axes)) for m in font.masters),
                str(font.familyName),_value(font.userData),parameters(font))

    def revalidate_match(self,ctx):
        self.assert_main()
        for target in ctx['targets']:
            revalidate(self,target); self.check_replace(target.layer)
        if self.axis_state(ctx['font'])!=ctx['axis_fingerprint']:
            raise CompanionError('Axis or master configuration changed; prepare again')
        if self.glyph_state(ctx['glyph'])!=ctx['glyph_fingerprint']:
            raise CompanionError('Glyph metadata changed; prepare again')
        from .matching_raster import revalidate_sources
        revalidate_sources(self,ctx)

    def hoi_available(self):
        self.assert_main()
        # Evaluator evidence is currently limited to this exact Glyphs build.
        if int(self.app.buildNumber)!=4108: return False
        try:
            import objc
            objc.lookUpClass('HOIWindow'); objc.lookUpClass('HOI')
            return True
        except Exception: return False

    @staticmethod
    def has_hoi(layer):
        return any(bool(call(n,'attributeForKey_','hoi')) for p in layer.paths for n in p.nodes)

    def existing_hoi(self,stage):
        def plain(value):
            if hasattr(value,'keys'): return {str(k):plain(value[k]) for k in value.keys()}
            if isinstance(value,str): return str(value)
            if isinstance(value,(int,float)): return float(value)
            return [plain(v) for v in value]
        axis=stage['context']['axis']['tag']; result=[]
        for mi,layer in enumerate(stage['layers']):
            for ci,path in enumerate(layer.paths):
                for ni,node in enumerate(path.nodes):
                    value=call(node,'attributeForKey_','hoi') or {}
                    if axis in value: result.append(dict(master=mi,contour=ci,node=ni,settings=plain(value[axis])))
                    if set(value)-{axis}: raise CompanionError('HOI for another axis cannot be exchanged in this single-axis master set')
        return result

    def block_writes(self):
        type(self).writes_blocked=True

    def stage(self,ctx,result):
        self.revalidate_match(ctx)
        # Native copy preserves evaluator context; only selected glyph is edited.
        font=call(ctx['font'],'copy'); call(font,'setParent_',None)
        glyph=font.glyphs[ctx['glyph'].name]
        manager=glyph.undoManager()
        if manager is not None:
            if self.same(manager,ctx['glyph'].undoManager()):
                raise CompanionError('Detached copy shares the source Undo manager')
            manager.disableUndoRegistration()
        layers=[glyph.layers[t.owner.layerId] for t in ctx['targets']]
        for mi,(layer,role) in enumerate(zip(layers,('reference','target'))):
            source_paths=list(layer.paths); current=ctx['outlines'][mi]
            output=result[role]['outline']
            if self.has_hoi(layer) and current!=output:
                raise CompanionError('Matching would invalidate existing HOI; use unchanged compatible outlines or review it manually')
            previous=self.rounding_state(layer)
            try:
                self.set_rounding(layer,True)
                # Hints belong to the live source nodes, not this geometry-only
                # preview. Transfer is checked separately just before Apply.
                layer.hints=[]
                maps_match=current==result['sourceMasters'][mi]['outline']
                native=self.make_paths(output['contours'])
                for ci,path in enumerate(native):
                    report=result['contours'][ci]
                    source_ci=ci if mi==0 else report['targetContour']
                    old=source_paths[source_ci] if maps_match and source_ci<len(source_paths) else None
                    mapping=report['referenceSourceNodes' if mi==0 else 'targetSourceNodes']
                    if old is not None:
                        path=old.copy()
                        fresh=self.make_paths([output['contours'][ci]])[0]
                        kept=set(v for v in mapping if v is not None)
                        for index,node in enumerate(old.nodes):
                            if index not in kept and (node.name or bool(node.userData) or bool(call(node,'attributes'))):
                                raise CompanionError('Matching would remove an annotated node; revise the source or mapping')
                        nodes=[]
                        for new,index,wanted in zip(fresh.nodes,mapping,output['contours'][ci]['nodes']):
                            if index is not None:
                                new=old.nodes[index].copy(); new.position=(wanted['x'],wanted['y'])
                                if new.type!=self.types[wanted['type']]: new.type=self.types[wanted['type']]
                                if bool(new.smooth)!=wanted['smooth']: new.smooth=wanted['smooth']
                            nodes.append(new)
                        call(path,'setNodes_',nodes)
                        native[ci]=path
                    elif any(p.attributes or any(n.name or bool(n.userData) or bool(call(n,'attributes')) for n in p.nodes) for p in source_paths):
                        raise CompanionError('Imported sources differ from annotated destination paths; metadata cannot be mapped safely')
                layer.shapes=native
            finally:
                self.set_rounding(layer,previous)
                if self.rounding_state(layer)!=previous:
                    raise CompanionError('Detached precision state restoration failed')
            actual=dict(contours=[self.path_data(p) for p in layer.paths])
            self.verify_outline(actual,output)
        return dict(font=font,layers=layers,context=ctx)

    @staticmethod
    def verify_outline(actual,wanted):
        a,b=actual['contours'],wanted['contours']
        if len(a)!=len(b): raise CompanionError('Native contour readback mismatch')
        for p,q in zip(a,b):
            if p['closed']!=q['closed'] or len(p['nodes'])!=len(q['nodes']): raise CompanionError('Native structure readback mismatch')
            for n,m in zip(p['nodes'],q['nodes']):
                if n['type']!=m['type'] or n['smooth']!=m['smooth'] or max(abs(n[k]-m[k]) for k in ('x','y'))>1e-7:
                    raise CompanionError('Native matching readback differs (1e-7 units)')

    def stage_paths(self,stage):
        return [[self.path_data(p) for p in layer.paths] for layer in stage['layers']]

    def staged_states(self,stage):
        return [tuple(self.shape_state(s) for s in layer.shapes) for layer in stage['layers']]

    def install_stage(self,ctx,stage):
        from .matching_hints import install
        for target,layer,transfer in zip(ctx['targets'],stage['layers'],stage['hint_transfers']):
            install(self,target.layer,layer,transfer)

    def prepare_apply_stage(self,ctx,stage,result):
        from .matching_hints import prepare
        return prepare(self,ctx,stage,result)

    def snapshot(self,layer):
        snapshot=super().snapshot(layer)
        snapshot['hints']=list(_native_items(layer.hints))
        return snapshot

    def restore(self,layer,snapshot):
        if [self.shape_state(s) for s in snapshot['shapes']]==snapshot['shapeStates']:
            layer.hints=[]
            layer.shapes=snapshot['shapes']; layer.hints=snapshot['hints']
            layer.width=snapshot['width']
            if self.preserved_state(layer)==snapshot['preserved']:
                return
        # Copy paths and hints together so backup references remain coherent.
        backup=snapshot['layer'].copy()
        layer.hints=[]
        layer.shapes=list(backup.shapes); layer.hints=list(_native_items(backup.hints))
        layer.width=snapshot['width']

    def verify_stage(self,ctx,stage,snapshots):
        from .matching_hints import verify
        for target,layer,snapshot,transfer in zip(ctx['targets'],stage['layers'],snapshots,stage['hint_transfers']):
            self.verify_outline(dict(contours=[self.path_data(p) for p in target.layer.paths]),
                                dict(contours=[self.path_data(p) for p in layer.paths]))
            if tuple(self.shape_state(s) for s in target.layer.shapes)!=tuple(self.shape_state(s) for s in layer.shapes):
                raise CompanionError('Native node attributes differ from prepared settings')
            actual=self.preserved_state(target.layer); expected=snapshot['preserved']
            # Hint indices intentionally follow the new node order. Verify those
            # references and settings explicitly, retaining every other datum.
            if actual[:4]+actual[5:]!=expected[:4]+expected[5:] or transfer['keep'] and actual[4]!=expected[4]:
                raise CompanionError('Matching changed non-path layer data')
            verify(self,target.layer,transfer)
