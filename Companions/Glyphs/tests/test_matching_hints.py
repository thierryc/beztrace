# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Exercise production native staging/transactions with detached identity-aware doubles."""
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from test_matching import ENGINE, result, finish
from beztrace_companion import matching, matching_hints
from beztrace_companion.contract import CompanionError
from beztrace_companion.matching_native import MatchingHost


class NativePropertyTests(unittest.TestCase):
    def test_copied_native_getters_compare_values_and_detect_real_changes(self):
        class RawHint:
            type=0
            def __init__(self): self.data={'custom':'preserve'}
            def userData(self): return self.data
            def scale(self): return (1.,1.)
        hint=RawHint(); clone=copy.deepcopy(hint)
        self.assertEqual(matching_hints.metadata(hint),matching_hints.metadata(clone))
        values=dict(matching_hints.metadata(hint))
        self.assertEqual(values['userData'],(('custom','preserve'),))
        self.assertEqual(values['scale'],(1.,1.))
        clone.data['custom']='changed'
        self.assertNotEqual(matching_hints.metadata(hint),matching_hints.metadata(clone))

    def test_unreadable_native_getter_is_not_hidden_by_a_description(self):
        class BrokenHint:
            def userData(self): raise RuntimeError('native read failed')
        with self.assertRaisesRegex(RuntimeError,'native read failed'):
            matching_hints.metadata(BrokenHint())


class Native:
    @property
    def pyobjc_instanceMethods(self):
        obj=self
        class Bridge:
            def __getattr__(self,key):
                value=getattr(obj,key)
                return value if callable(value) else lambda:value
        return Bridge()
    def copy(self): return copy.deepcopy(self)


class Node(Native):
    @property
    def position(self): return self._position
    @position.setter
    def position(self,value):
        self._position=value if hasattr(value,'x') else SimpleNamespace(x=value[0],y=value[1])
    def __init__(self,position,kind):
        self.position=SimpleNamespace(x=position[0],y=position[1]); self.type=kind
        self.smooth=False; self.name=None; self.userData={}; self.attributes={}
        self.connection=0; self.orientation=0
    def isLocked(self): return False
    def attributeForKey_(self,key): return self.attributes.get(key)


class Path(Native):
    def __init__(self): self.nodes=[]; self.closed=True; self.attributes={}; self.locked=False
    def isLocked(self): return self.locked
    def setNodes_(self,nodes): self.nodes=nodes


class Hint(Native):
    def __init__(self,layer,refs=(None,None,None,None),corner=False):
        self.parent=layer; self.type=1; self.horizontal=True; self.options=17
        self.name='test'; self.scale=(1.,1.); self.stem=3; self.alignment=2
        self.userData={'custom':'preserve'}; self.isCorner=corner
        self.position=21.; self.width=42.
        for (name,_),ref in zip(matching_hints.REFERENCES,refs): setattr(self,name,ref)
    def copy(self):
        # Native hint copies retain their node attachments until explicitly rebound.
        clone=copy.copy(self); clone.userData=copy.deepcopy(self.userData)
        return clone
    def index(self,name):
        node=getattr(self,name)
        if node is None: return None
        return next(([ci,ni] for ci,p in enumerate(self.parent.paths) for ni,n in enumerate(p.nodes) if n is node),[999,999])
    origin=property(lambda self:self.index('originNode'))
    target=property(lambda self:self.index('targetNode'))
    other1=property(lambda self:self.index('otherNode1'))
    other2=property(lambda self:self.index('otherNode2'))


class Layer(Native):
    def __init__(self,paths,name):
        self.shapes=paths; self._hints=[]; self.width=500.; self.name=name; self.layerId=name
        self.anchors=[]; self.guides=[]; self.annotations=[]; self.backgroundImage=None; self.rounding=False
    paths=property(lambda self:self.shapes)
    @property
    def hints(self): return self._hints
    @hints.setter
    def hints(self,hints):
        self._hints=list(hints)
        for hint in self._hints: hint.parent=self
    def temporarilyDisableRounding(self): return self.rounding
    def setTemporarilyDisableRounding_(self,value): self.rounding=value


class Glyph(Native):
    def undoManager(self): return None


class Font(Native):
    def setParent_(self,parent): self.parent=parent


class NativeHost(MatchingHost):
    def __init__(self,packet):
        self.Path=Path; self.Node=Node; self.types={'line':1,'curve':2,'offcurve':3}
        self.same=lambda a,b:a is not None and a is b
        self.font=Font(); self.glyph=Glyph(); self.glyph.name='A'; self.font.glyphs={'A':self.glyph}
        self.layers=[Layer(self.make_paths(m['outline']['contours']),str(i)) for i,m in enumerate(packet['sourceMasters'])]
        self.glyph.layers={l.layerId:l for l in self.layers}
        for l in self.layers: l.parent=self.glyph
        self.present=True; self.events=[]; self.fail=None
    def assert_main(self): pass
    def context(self,font,glyph,reference_id):
        for layer in self.layers: self.check_replace(layer)
        return dict(font=self.font,glyph=self.glyph,
            targets=[SimpleNamespace(layer=l,owner=l) for l in self.layers],
            outlines=[dict(contours=[self.path_data(p) for p in l.paths]) for l in self.layers],
            axis=dict(tag='wght',locations=[100,900]),unitsPerEm=1000,
            fingerprints=[self.fingerprint(l) for l in self.layers])
    def revalidate_match(self,ctx):
        if not self.present or [self.fingerprint(l) for l in self.layers]!=ctx['fingerprints']:
            raise CompanionError('stale target')
    def hoi_available(self): return False
    def begin_undo(self,glyph): self.events.append('begin')
    def end_undo(self,glyph): self.events.append('end')
    def redraw(self): self.events.append('redraw')
    def install_stage(self,ctx,stage):
        super().install_stage(ctx,stage)
        if self.fail=='install': raise RuntimeError('second master failed')
    def verify_stage(self,ctx,stage,snapshots):
        if self.fail=='corrupt-hint': self.layers[1].hints[0].originNode=self.layers[1].paths[0].nodes[0]
        super().verify_stage(ctx,stage,snapshots)
        if self.fail=='verify': raise RuntimeError('post-install failure')


class HintTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.packet=result()
    def setUp(self): self.host=NativeHost(self.packet)
    def attach(self,master,indices=(0,1,2,3),**kwargs):
        layer=self.host.layers[master]
        hint=Hint(layer,[layer.paths[0].nodes[i] if i is not None else None for i in indices],**kwargs)
        layer.hints.append(hint)
        return hint
    def prepare(self):
        return finish(matching.prepare_match(self.host.font,'A','0',settings=dict(repairHOI=False),
                      engine=str(ENGINE),_host=self.host))
    def test_hint_does_not_block_native_preview_and_source_is_untouched(self):
        self.attach(0); self.attach(1)
        before=[self.host.fingerprint(l) for l in self.host.layers]
        plan=self.prepare()
        self.assertEqual([self.host.fingerprint(l) for l in self.host.layers],before)
        self.assertEqual(self.host.events,[])
        self.assertTrue(all(not l.hints for l in plan.stage['layers']))
        self.assertEqual(plan.result['target']['outline'],self.packet['target']['outline'])
    def test_apply_rebinds_all_four_references_and_preserves_settings(self):
        ref=self.attach(0); hint=self.attach(1)
        before=matching_hints.metadata(hint); plan=self.prepare()
        original=list(self.host.layers[0].paths)
        matching.apply_match(plan)
        self.assertIs(self.host.layers[0].hints[0],ref)
        self.assertIs(self.host.layers[0].paths[0],original[0])
        installed=self.host.layers[1].hints[0]
        self.assertEqual(matching_hints.metadata(installed),before)
        mapping=matching_hints.node_map(plan.context['outlines'][1],plan.result,1)
        for (name,_),old in zip(matching_hints.REFERENCES,range(4)):
            ci,ni=mapping[(0,old)]
            self.assertIs(getattr(installed,name),self.host.layers[1].paths[ci].nodes[ni])
        self.assertEqual(self.host.events,['begin','end','redraw'])
    def test_native_copy_omitting_user_data_is_repaired_before_apply(self):
        hint=self.attach(1); before=matching_hints.metadata(hint)
        original_copy=Hint.copy
        def native_copy(source):
            clone=original_copy(source); clone.userData={}; return clone
        with patch.object(Hint,'copy',native_copy):
            plan=self.prepare(); matching.apply_match(plan)
        self.assertEqual(matching_hints.metadata(self.host.layers[1].hints[0]),before)

    def test_hint_metadata_is_set_while_detached_before_collection_undo(self):
        class NativeCopyHint(Hint):
            def copy(self):
                clone=copy.copy(self); clone.parent=None; clone.userData={}; return clone
            def setUserData_(self,value):
                if self.parent is not None:
                    raise RuntimeError('attached metadata setter adds native Undo operations')
                self.userData=value
        layer=self.host.layers[1]
        hint=NativeCopyHint(layer,[layer.paths[0].nodes[i] for i in range(4)])
        layer.hints.append(hint); before=matching_hints.metadata(hint)
        plan=self.prepare(); matching.apply_match(plan)
        self.assertEqual(matching_hints.metadata(layer.hints[0]),before)

    def test_recovery_preserves_user_data_when_native_layer_copy_omits_it(self):
        self.attach(0); self.attach(1)
        original_copy=Layer.copy
        def native_copy(layer):
            clone=original_copy(layer)
            for hint in clone.hints: hint.userData={}
            return clone
        before=[self.host.fingerprint(layer) for layer in self.host.layers]
        with patch.object(Layer,'copy',native_copy):
            plan=self.prepare(); self.host.fail='install'
            with self.assertRaisesRegex(CompanionError,'both master layers were restored'):
                matching.apply_match(plan)
        self.assertEqual([self.host.fingerprint(layer) for layer in self.host.layers],before)
        self.assertFalse(plan.poisoned)

    def test_ghost_and_absolute_hints_are_preserved(self):
        self.attach(1,(0,None,None,None)); absolute=self.attach(1,(None,None,None,None))
        plan=self.prepare(); matching.apply_match(plan)
        installed=self.host.layers[1].hints
        self.assertIsNone(installed[0].targetNode)
        self.assertEqual((installed[1].position,installed[1].width),(absolute.position,absolute.width))
        self.assertEqual(matching_hints.metadata(installed[1]),matching_hints.metadata(absolute))
    def test_unmappable_hint_blocks_apply_before_undo_and_preserves_preview(self):
        self.attach(1,(0,None,None,None)); plan=self.prepare()
        # Raster/import source IDs cannot stand in for destination path IDs.
        plan.result=copy.deepcopy(plan.result)
        plan.result['sourceMasters'][1]['outline']['contours'][0]['nodes'][0]['x']+=1
        before=[self.host.fingerprint(l) for l in self.host.layers]
        with self.assertRaisesRegex(matching_hints.HintMappingError,'node replaced'):
            matching.apply_match(plan)
        self.assertEqual(before,[self.host.fingerprint(l) for l in self.host.layers])
        self.assertFalse(plan.consumed); self.assertTrue(plan.apply_error)
        self.assertIsNotNone(plan.stage); self.assertEqual(self.host.events,[])
    def test_removed_and_retyped_nodes_are_not_guessed(self):
        self.attach(1,(0,None,None,None)); plan=self.prepare()
        for change in ('removed','retyped','duplicate'):
            packet=copy.deepcopy(plan.result)
            mapping=packet['contours'][0]['targetSourceNodes']
            index=mapping.index(0)
            if change=='removed': mapping[index]=None
            elif change=='duplicate': mapping[(index+1)%len(mapping)]=0
            else: packet['target']['outline']['contours'][0]['nodes'][index]['type']='curve'
            with self.subTest(change=change), self.assertRaises(matching_hints.HintMappingError):
                matching_hints.prepare(self.host,plan.context,plan.stage,packet)
    def test_unsupported_attachment_previews_then_refuses_apply(self):
        self.attach(1,(None,None,None,None)).originNode=object()
        plan=self.prepare()
        with self.assertRaisesRegex(matching_hints.HintMappingError,'attachment'):
            matching.apply_match(plan)
        self.assertFalse(plan.consumed); self.assertEqual(self.host.events,[])
    def test_hint_edits_after_preview_invalidate_before_write(self):
        hint=self.attach(1); plan=self.prepare(); hint.stem=4
        with self.assertRaisesRegex(CompanionError,'stale'): matching.apply_match(plan)
        self.assertEqual(self.host.events,[])
    def test_unaffected_unsupported_hint_is_kept_on_unchanged_reference(self):
        hint=self.attach(0,(None,None,None,None)); hint.originNode=object()
        plan=self.prepare(); matching.apply_match(plan)
        self.assertIs(self.host.layers[0].hints[0],hint)
    def test_image_preview_with_hints_defers_unmappable_destination_check(self):
        hint=self.attach(1,(0,None,None,None))
        packet=copy.deepcopy(self.packet)
        # Emulate a raster-derived source whose indices do not name the live paths.
        packet['sourceMasters'][1]['outline']['contours'][0]['nodes'][0]['x']+=1
        with patch('beztrace_companion.matching_raster.capture',return_value=[]), \
             patch('beztrace_companion.matching_raster.prepare_sources',return_value=[]), \
             patch.object(matching.contract,'match',return_value=packet):
            plan=finish(matching.prepare_match(self.host.font,'A','0',source_mode=2,
                        settings=dict(repairHOI=False,referencePolicy='shared-subdivision'),_host=self.host))
        self.assertIsNotNone(plan.stage); self.assertIs(self.host.layers[1].hints[0],hint)
        with self.assertRaises(matching_hints.HintMappingError): matching.apply_match(plan)
        self.assertEqual(self.host.events,[])
    def test_image_sources_do_not_block_absolute_hints(self):
        hint=self.attach(1,(None,None,None,None))
        plan=self.prepare(); plan.result=copy.deepcopy(plan.result)
        plan.result['sourceMasters'][1]['outline']['contours'][0]['nodes'][0]['x']+=1
        matching.apply_match(plan)
        installed=self.host.layers[1].hints[0]
        self.assertEqual(matching_hints.metadata(installed),matching_hints.metadata(hint))
        self.assertEqual((installed.position,installed.width),(hint.position,hint.width))
    def test_corner_with_preserved_adjacency_survives_cyclic_start_change(self):
        self.attach(1,(0,None,None,None),corner=True)
        plan=self.prepare(); matching.apply_match(plan)
        self.assertTrue(self.host.layers[1].hints[0].isCorner)
    def test_hint_copy_failure_is_apply_only_and_does_not_consume_preview(self):
        hint=self.attach(1); plan=self.prepare()
        with patch.object(hint,'copy',side_effect=RuntimeError('unsupported native hint copy')):
            with self.assertRaisesRegex(matching_hints.HintMappingError,'could not be verified'):
                matching.apply_match(plan)
        self.assertFalse(plan.consumed); self.assertEqual(self.host.events,[])
    def test_partial_apply_and_bad_readback_restore_paths_hints_and_precision(self):
        for phase in ('install','verify','corrupt-hint'):
            self.host=NativeHost(self.packet); ref=self.attach(0); target=self.attach(1)
            self.host.layers[0].rounding=True; plan=self.prepare()
            before=[self.host.fingerprint(l) for l in self.host.layers]
            old_node=target.originNode; self.host.fail=phase
            with self.subTest(phase=phase), self.assertRaisesRegex(CompanionError,'both master layers were restored'):
                matching.apply_match(plan)
            self.assertEqual([self.host.fingerprint(l) for l in self.host.layers],before)
            self.assertIs(self.host.layers[0].hints[0],ref)
            self.assertIs(self.host.layers[1].hints[0],target)
            self.assertIs(target.originNode,old_node)
            self.assertEqual([l.rounding for l in self.host.layers],[True,False])
            self.assertEqual(self.host.events,['begin','end'])


class HintCorrespondenceTests(unittest.TestCase):
    def test_contour_permutation_and_inserted_node_keep_exact_source_identity(self):
        def contour(x): return dict(closed=True,nodes=[dict(x=x+i,y=i,type='line',smooth=False) for i in range(3)])
        a,b=contour(0),contour(10); source=dict(contours=[a,b])
        output=dict(contours=[copy.deepcopy(b),copy.deepcopy(a)])
        output['contours'][0]['nodes'].insert(1,dict(x=10.5,y=.5,type='line',smooth=False))
        packet=dict(target=dict(outline=output),sourceMasters=[{},dict(outline=source)],
                    contours=[dict(targetContour=1,targetSourceNodes=[0,None,1,2]),
                              dict(targetContour=0,targetSourceNodes=[0,1,2])])
        mapping=matching_hints.node_map(source,packet,1)
        self.assertEqual(mapping[(1,1)],(0,2)); self.assertEqual(mapping[(0,2)],(1,2))
        self.assertNotIn((0,1),mapping.values())

    def test_corner_attachment_cannot_cross_a_new_neighbor(self):
        packet=result(); host=NativeHost(packet)
        layer=host.layers[1]
        layer.hints=[Hint(layer,[layer.paths[0].nodes[0],None,None,None],corner=True)]
        ctx=host.context(None,'A','0')
        stage=host.stage(ctx,packet)
        mapping=matching_hints.node_map(ctx['outlines'][1],packet,1)
        with patch.object(matching_hints,'node_map',return_value={k:v for k,v in mapping.items() if k!=(0,1)}):
            with self.assertRaisesRegex(matching_hints.HintMappingError,'corner or cap'):
                matching_hints.prepare(host,ctx,stage,packet)


if __name__=='__main__': unittest.main()
