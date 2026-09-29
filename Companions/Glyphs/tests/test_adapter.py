# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
from types import SimpleNamespace
import unittest
from test_contract import sample,contour
from beztrace_companion.adapter import capture,revalidate,apply_paths,RecoveryError
from beztrace_companion.contract import CompanionError,signed_area
from beztrace_companion.native import GlyphsHost


class Layer:
    def __init__(self,width=0):
        self.shapes=['existing path','component']; self.width=width
        self.anchors=[('top',50,100)]; self.rounding=False


class FakeHost:
    def __init__(self):
        self.document=object(); self.font=object(); self.glyph=object(); self.owner=Layer()
        self.background=Layer(); self.present=True; self.editable=True; self.main=True
        self.ids=('glyph1','layer1'); self.undo=0; self.events=[]; self.fail=None; self.restore_fail=False
    def assert_main(self):
        if not self.main: raise CompanionError('main thread')
    def current(self): return self.document,self.font,self.glyph,self.owner
    def destination(self,owner,destination): return self.background if destination=='background' else owner
    def check_editable(self,glyph,layer):
        if not self.editable: raise CompanionError('locked')
    def check_replace(self,layer): pass
    def identity(self,glyph,owner): return self.ids
    def label(self,*args): return 'Disposable / A / Regular'
    def contains(self,t): return self.present and self.ids==t.identity and self.destination(t.owner,t.destination) is t.layer
    def fingerprint(self,layer): return copy.deepcopy((layer.shapes,layer.width,layer.anchors))
    def make_paths(self,paths): return copy.deepcopy(paths)
    def snapshot(self,layer): return self.fingerprint(layer)
    def rounding_state(self,layer): return layer.rounding
    def set_rounding(self,layer,value): layer.rounding=value
    def begin_undo(self,glyph): self.undo+=1; self.events.append('begin')
    def end_undo(self,glyph): self.undo-=1; self.events.append('end')
    def insert(self,layer,paths,replace):
        if replace: layer.shapes=[s for s in layer.shapes if s=='component']
        for path in paths:
            layer.shapes.append(path)
            if self.fail=='insert': raise RuntimeError('insertion fault')
    def restore(self,layer,snapshot):
        if self.restore_fail: raise RuntimeError('recovery fault')
        layer.shapes,layer.width,layer.anchors=copy.deepcopy(snapshot)
    def verify(self,layer,native,expected,snapshot,replace):
        if self.fail=='verify': raise RuntimeError('readback mismatch')
        assert layer.shapes[-len(expected):]==expected
        assert layer.width==snapshot[1] and layer.anchors==snapshot[2]
    def redraw(self): self.events.append('redraw')


class TransactionTests(unittest.TestCase):
    def test_append_preserves_zero_width_and_content(self):
        host=FakeHost(); target=capture(host,'foreground')
        apply_paths(host,target,sample()['paths'])
        self.assertEqual(host.owner.shapes[:2],['existing path','component'])
        self.assertEqual(host.owner.width,0); self.assertEqual(host.undo,0)
        self.assertEqual(host.events,['begin','end','redraw'])

    def test_live_replacement_preserves_original_and_recovers_last_trace(self):
        host=FakeHost(); base=host.snapshot(host.owner)
        apply_paths(host,capture(host,'foreground'),sample()['paths'])
        previous=host.fingerprint(host.owner)
        changed=copy.deepcopy(sample()['paths']); changed[0]['nodes'][0]['x']+=1
        apply_paths(host,capture(host,'foreground'),changed,base_snapshot=base)
        self.assertEqual(len(host.owner.shapes),3)
        self.assertEqual(host.owner.shapes[:2],base[0])
        self.assertEqual(host.owner.shapes[-1],changed[0])
        previous=host.fingerprint(host.owner)
        host.fail='verify'
        with self.assertRaisesRegex(CompanionError,'restored'):
            apply_paths(host,capture(host,'foreground'),sample()['paths'],base_snapshot=base)
        self.assertEqual(host.fingerprint(host.owner),previous)
        self.assertEqual(host.undo,0)
        target=capture(host,'foreground'); host.owner.shapes.append('user edit')
        with self.assertRaisesRegex(CompanionError,'destination changed'):
            apply_paths(host,target,changed,base_snapshot=base)
        self.assertEqual(host.owner.shapes[-1],'user edit')

    def test_replace_preserves_components_anchors_width(self):
        host=FakeHost(); host.owner.width=600; target=capture(host,'foreground')
        apply_paths(host,target,sample()['paths'],True)
        self.assertEqual(host.owner.shapes[0],'component'); self.assertEqual(len(host.owner.shapes),2)
        self.assertEqual(host.owner.width,600); self.assertEqual(host.owner.anchors,[('top',50,100)])

    def test_background_leaves_foreground_untouched(self):
        host=FakeHost(); before=host.fingerprint(host.owner)
        apply_paths(host,capture(host,'background'),sample()['paths'])
        self.assertEqual(host.fingerprint(host.owner),before)
        self.assertEqual(len(host.background.shapes),3)

    def test_closed_deleted_or_replaced_targets(self):
        for mutation in [lambda h:setattr(h,'present',False),lambda h:setattr(h,'ids',('new','layer1')),
                         lambda h:setattr(h,'ids',('glyph1','replacement')),
                         lambda h:setattr(h,'background',Layer())]:
            host=FakeHost(); target=capture(host,'background'); mutation(host)
            with self.assertRaises(CompanionError): apply_paths(host,target,sample()['paths'])
            self.assertEqual(host.events,[])

    def test_navigation_does_not_retarget(self):
        host=FakeHost(); target=capture(host,'foreground'); host.document=object()
        # The original document remains in the mock document collection.
        apply_paths(host,target,sample()['paths'])
        self.assertEqual(len(target.layer.shapes),3)

    def test_content_change_rejected(self):
        for change in [lambda l:l.shapes.append('edit'),lambda l:setattr(l,'width',50),lambda l:l.anchors.clear()]:
            host=FakeHost(); target=capture(host,'foreground'); change(host.owner)
            with self.assertRaises(CompanionError): revalidate(host,target)

    def test_locked_and_wrong_thread(self):
        for field in ['editable','main']:
            host=FakeHost(); target=capture(host,'foreground'); setattr(host,field,False)
            with self.assertRaises(CompanionError): apply_paths(host,target,sample()['paths'])
            self.assertEqual(host.events,[])

    def test_rollback_and_rounding_restoration(self):
        for phase in ['insert','verify']:
            for rounding in [False,True]:
                host=FakeHost(); host.fail=phase; host.owner.rounding=rounding
                target=capture(host,'foreground'); before=host.fingerprint(host.owner)
                with self.assertRaisesRegex(CompanionError,'restored'): apply_paths(host,target,sample()['paths'],True)
                self.assertEqual(host.fingerprint(host.owner),before)
                self.assertEqual(host.owner.rounding,rounding); self.assertEqual(host.undo,0)

    def test_recovery_failure_is_explicit(self):
        host=FakeHost(); host.fail='verify'; host.restore_fail=True
        with self.assertRaises(RecoveryError): apply_paths(host,capture(host,'foreground'),sample()['paths'])
        self.assertEqual(host.undo,0); self.assertFalse(host.owner.rounding)

    def test_precision_capability_fails_before_undo(self):
        host=FakeHost(); target=capture(host,'foreground')
        def missing(layer): raise CompanionError('precision unavailable')
        host.rounding_state=missing
        with self.assertRaises(CompanionError): apply_paths(host,target,sample()['paths'])
        self.assertEqual(host.events,[])

    def test_cleanup_attempts_end_undo_on_flag_failure(self):
        host=FakeHost(); target=capture(host,'foreground')
        def broken(layer,value):
            if not value: raise RuntimeError('flag fault')
            layer.rounding=value
        host.set_rounding=broken
        with self.assertRaises(RecoveryError): apply_paths(host,target,sample()['paths'])
        self.assertEqual(host.undo,0)


    def test_redraw_failure_does_not_make_apply_retryable(self):
        host=FakeHost()
        def broken(): raise RuntimeError('redraw fault')
        host.redraw=broken
        warning=apply_paths(host,capture(host,'foreground'),sample()['paths'])
        self.assertIn('Paths applied',warning)
        self.assertEqual(len(host.owner.shapes),3)


class Node:
    def __init__(self,point,kind):
        self.position=SimpleNamespace(x=point[0],y=point[1]); self.type=kind; self.smooth=False
class Path:
    def __init__(self): self.nodes=[]; self.closed=False


class NativeConstructionTests(unittest.TestCase):
    def test_maps_native_constants_without_changing_geometry(self):
        host=GlyphsHost.__new__(GlyphsHost); host.Path=Path; host.Node=Node
        host.types={'line':'native-line','curve':'native-curve','offcurve':'native-handle'}
        wanted=contour([(0.25,0.75),(100.5,0.75),(100.5,100.25),(0.25,100.25)],['curve','line','offcurve','offcurve'])
        wanted['nodes'][0]['smooth']=True
        native=host.make_paths([wanted])
        self.assertEqual(host.path_data(native[0]),wanted)
        self.assertTrue(native[0].closed)
        self.assertEqual(native[0].nodes[2].type,'native-handle')
        self.assertGreater(signed_area(host.path_data(native[0])),0)


    def test_native_membership_uses_object_identity(self):
        host=GlyphsHost.__new__(GlyphsHost)
        host.same=lambda a,b:a is b
        doc=object()
        font=SimpleNamespace(parent=doc,glyphs=[])
        glyph=SimpleNamespace(parent=font,layers=[],id='g')
        layer=SimpleNamespace(layerId='master')
        glyph.layers=[layer]; font.glyphs=[glyph]
        host.app=SimpleNamespace(documents=[doc])
        target=SimpleNamespace(document=doc,font=font,glyph=glyph,owner=layer,layer=layer,
                               destination='foreground',identity=('g','master'))
        self.assertTrue(host.contains(target))
        # A different native object with identical IDs/content must not match.
        glyph.layers=[SimpleNamespace(layerId='master')]
        self.assertFalse(host.contains(target))
        glyph.layers=[layer]; host.app.documents=[]
        self.assertFalse(host.contains(target))

    def test_native_readback_rejects_rounding_and_reordering(self):
        host=GlyphsHost.__new__(GlyphsHost)
        host.Path=Path; host.Node=Node; host.same=lambda a,b:a is b
        host.types={'line':'native-line','curve':'native-curve','offcurve':'native-handle'}
        host.preserved_state=lambda layer: ('width',layer.width)
        wanted=sample()['paths']
        native=host.make_paths(wanted)
        # Native direction is a read-only integer in Glyphs; supply its observed value here.
        native[0].direction=1
        layer=SimpleNamespace(shapes=native,width=600)
        snapshot={'shapes':[],'shapeStates':[],'preserved':('width',600)}
        host.verify(layer,native,wanted,snapshot,False)
        native[0].nodes[0].position.x+=.5
        with self.assertRaises(CompanionError): host.verify(layer,native,wanted,snapshot,False)
        native[0].nodes[0].position.x-=.5
        native[0].nodes=list(reversed(native[0].nodes))
        with self.assertRaises(CompanionError): host.verify(layer,native,wanted,snapshot,False)


class NullableNativeCollection:
    """Match SDK ListProxy when a native optional array has not been allocated."""
    def __init__(self, values=None): self.entries=values
    def values(self): return self.entries
    def __iter__(self): return iter(self.values())
    def __len__(self): return len(self.values())


class NullableCollectionTests(unittest.TestCase):
    def native_host(self):
        host=GlyphsHost.__new__(GlyphsHost); host.Path=Path
        return host

    def layer(self):
        return SimpleNamespace(shapes=[],paths=[],width=600,anchors=[],guides=[],
                               annotations=[],hints=[],backgroundImage=None)

    def test_capture_empty_optional_native_collections(self):
        native=self.native_host(); host=FakeHost(); layer=self.layer()
        host.owner=layer; host.fingerprint=native.fingerprint
        expected=native.fingerprint(layer)
        for key in ('guides','annotations','hints','anchors'):
            setattr(layer,key,NullableNativeCollection())
        target=capture(host,'foreground')
        self.assertEqual(target.fingerprint,expected)
        revalidate(host,target)

    def test_later_annotation_still_invalidates_capture(self):
        native=self.native_host(); host=FakeHost(); host.owner=self.layer()
        host.fingerprint=native.fingerprint
        host.owner.annotations=NullableNativeCollection()
        target=capture(host,'foreground')
        host.owner.annotations.entries=[SimpleNamespace(text='New annotation')]
        with self.assertRaisesRegex(CompanionError,'destination changed'): revalidate(host,target)

    def test_nil_hints_allow_replace_but_existing_hints_block_it(self):
        host=self.native_host(); layer=self.layer(); layer.hints=NullableNativeCollection()
        host.check_replace(layer)
        layer.hints.entries=[object()]
        with self.assertRaisesRegex(CompanionError,'hints'): host.check_replace(layer)

    def test_unexpected_collection_read_error_is_not_hidden(self):
        class BrokenCollection(NullableNativeCollection):
            def values(self): raise RuntimeError('Native read failed')
        layer=self.layer(); layer.guides=BrokenCollection()
        with self.assertRaisesRegex(RuntimeError,'Native read failed'):
            self.native_host().fingerprint(layer)

    def test_native_none_matches_empty_collection(self):
        layer=self.layer(); host=self.native_host(); expected=host.fingerprint(layer)
        layer.guides=layer.annotations=layer.hints=layer.anchors=None
        self.assertEqual(host.fingerprint(layer),expected)

    def test_nil_layer_and_font_metrics_fall_back_to_master(self):
        host=self.native_host(); host.assert_main=lambda:None
        master=SimpleNamespace(capHeight=700,xHeight=500,ascender=800,descender=-200)
        layer=SimpleNamespace(metrics=NullableNativeCollection(),master=master,
                              parent=SimpleNamespace(parent=SimpleNamespace(metrics=NullableNativeCollection())))
        result=host.read_metrics(layer,{1:'capHeight'})
        self.assertEqual(result.get('capHeight'),700)


class SelectionContextTests(unittest.TestCase):
    def host(self):
        host=GlyphsHost.__new__(GlyphsHost)
        host.assert_main=lambda:None
        host.same=lambda a,b:a is not None and a is b
        document=object()
        host.app=SimpleNamespace(font=SimpleNamespace(parent=document,currentTab=object()),documents=[document])
        return host

    def test_same_document_and_tab_allowed(self):
        host=self.host(); host.check_selection_context(host.selection_context())
        host.app.font.currentTab=None
        host.check_selection_context(host.selection_context())

    def test_switched_closed_or_replaced_context_rejected(self):
        for change in (lambda h:setattr(h.app.font,'currentTab',object()),
                       lambda h:setattr(h.app,'documents',[]),
                       lambda h:setattr(h.app,'font',SimpleNamespace(parent=h.app.font.parent,currentTab=h.app.font.currentTab)),
                       lambda h:setattr(h.app.font,'parent',object())):
            host=self.host(); context=host.selection_context(); change(host)
            with self.assertRaises(CompanionError): host.check_selection_context(context)

    def test_missing_font_or_document_rejected(self):
        for font in (None, SimpleNamespace(parent=None)):
            host=self.host(); host.app.font=font
            with self.assertRaises(CompanionError): host.selection_context()


if __name__=='__main__': unittest.main()
