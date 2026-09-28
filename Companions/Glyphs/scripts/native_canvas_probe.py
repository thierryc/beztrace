# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Disposable Glyphs 4 CLI qualification; no open document or installed plugin.

Run with glyphs run --app '/Applications/Glyphs 4.app' --plugins '' this-file.
Creates only detached GSFont objects and scratch PNG/JPEG fixtures under .build.
Document selection, menu loading and visible edit-view alignment need in-app tests.
"""
import sys
import os
import json
import threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Beztrace.glyphsPlugin/Contents/Resources'))
from AppKit import (NSBitmapImageRep,NSGraphicsContext,NSDeviceRGBColorSpace,NSColor,NSBezierPath,
                    NSBitmapImageFileTypePNG,NSMakeRect)
from Foundation import NSMutableData
from Quartz import (CGImageDestinationCreateWithData,CGImageDestinationAddImage,
    CGImageDestinationFinalize,kCGImagePropertyOrientation)
from GlyphsApp import Glyphs,GSFont,GSFontMaster,GSGlyph
from beztrace_companion.native import GlyphsHost
from beztrace_companion.adapter import Target,apply_paths,apply_image
from beztrace_companion import image_io
from beztrace_companion.engine import trace,DEFAULT_ENGINE
TEST_ENGINE = os.environ.get('BEZTRACE_TEST_ENGINE', DEFAULT_ENGINE)
from beztrace_companion.canvas import ImageGeometry,transform_paths
from beztrace_companion.contract import tight_bounds


def fixture(path,dpi=72,orientation=None):
    bitmap=NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(None,160,180,8,4,True,False,NSDeviceRGBColorSpace,0,0)
    context=NSGraphicsContext.graphicsContextWithBitmapImageRep_(bitmap)
    NSGraphicsContext.saveGraphicsState()
    try:
        NSGraphicsContext.setCurrentContext_(context)
        NSColor.whiteColor().set(); NSBezierPath.fillRect_(NSMakeRect(0,0,160,180))
        NSColor.blackColor().set(); NSBezierPath.fillRect_(NSMakeRect(20,30,70,90))
        NSColor.whiteColor().set(); NSBezierPath.fillRect_(NSMakeRect(40,50,20,30))
    finally: NSGraphicsContext.restoreGraphicsState()
    bitmap.setSize_((160*72/dpi,180*72/dpi))
    if orientation:
        data=NSMutableData.data()
        dest=CGImageDestinationCreateWithData(data,'public.jpeg',1,None)
        CGImageDestinationAddImage(dest,bitmap.CGImage(),{kCGImagePropertyOrientation:orientation})
        assert CGImageDestinationFinalize(dest)
        path.write_bytes(bytes(data))
    else: path.write_bytes(bytes(bitmap.representationUsingType_properties_(NSBitmapImageFileTypePNG,{})))


class DetachedHost(GlyphsHost):
    def contains(self,t):
        # Only replace document-membership checks: CLI fixtures have no document.
        return self.same(t.glyph.parent,t.font) and self.same(t.owner.parent,t.glyph)
    def target(self,font,glyph_name,layer_id,destination='foreground',sizing=False):
        assert font is self.fixture_font and glyph_name=='A' and layer_id==self.fixture_owner.layerId
        owner=self.fixture_owner; glyph=owner.parent
        layer=owner if destination=='foreground' else self.fixture_background
        return Target(None,font,glyph,owner,layer,destination,self.identity(glyph,owner),self.fingerprint(layer),
                      'Disposable API / A',self.metrics(owner) if sizing else None,self.classification(glyph) if sizing else None)
    def redraw(self): pass


def run():
    output=ROOT.parents[1]/'.build/glyphs-native-canvas'; output.mkdir(parents=True,exist_ok=True)
    host=DetachedHost()
    font=GSFont(); font.familyName='Beztrace Disposable Canvas Qualification'
    master=GSFontMaster(); font.masters.append(master)
    glyph=GSGlyph('A'); font.glyphs.append(glyph)
    layer=glyph.layers[master.id]; layer.width=0
    background=layer.background
    manager=glyph.undoManager()
    while manager.groupingLevel(): manager.endUndoGrouping()
    manager.removeAllActions(); manager.setGroupsByEvent_(False)
    def target(destination=layer):
        return Target(None,font,glyph,layer,destination,'background' if destination is background else 'foreground',
                      host.identity(glyph,layer),host.fingerprint(destination),'Disposable / A')
    cases=0
    for name,dpi,orientation in [('plain.png',72,None),('dpi144.png',144,None),('oriented.jpg',72,6)]:
        path=output/name; fixture(path,dpi,orientation)
        image=host.new_image(path)
        snap=image_io.snapshot(image)
        data,source_hash=image_io.prepare(snap,threading.Event())
        result=trace(TEST_ENGINE,data,{})
        identity=transform_paths(result,snap.geometry)
        bounds=tight_bounds(identity)
        print('IMAGE',name,'native size',snap.geometry.size,'raster',result['source']['width'],result['source']['height'],'ink',bounds)
        if orientation is None:
            factor=snap.geometry.size[0]/160
            for actual,wanted in zip(bounds,(20*factor,30*factor,90*factor,120*factor)):
                assert abs(actual-wanted)<1.5*factor,(actual,wanted)
        assert len(result['paths'])==2
        for matrix in [(1,0,0,1,13.25,-27.5),(0,1,-1,0,300.5,40.25),(-1.25,.2,.3,1.7,500,-120)]:
            image=host.new_image(path)
            image.transform=matrix
            target_before=target()
            apply_image(host,target_before,image,replace=layer.backgroundImage is not None)
            image_after=host.image_state(layer.backgroundImage)
            assert image_after==host.image_state(image)
            manager.undo()
            if host.fingerprint(layer)!=target_before.fingerprint:
                print('UNDO IMAGE BEFORE',target_before.fingerprint)
                print('UNDO IMAGE AFTER',host.fingerprint(layer))
                raise AssertionError('Image undo mismatch')
            manager.redo(); assert host.image_state(layer.backgroundImage)==image_after
            snapshot=image_io.snapshot(layer.backgroundImage)
            rendered,sha=image_io.prepare(snapshot,threading.Event())
            traced=trace(TEST_ENGINE,rendered,{})
            paths=transform_paths(traced,snapshot.geometry)
            before=target(); count=len(layer.paths)
            apply_paths(host,before,paths)
            assert layer.width==0 and len(layer.paths)==count+2
            assert host.image_state(layer.backgroundImage)==image_after
            manager.undo(); assert host.fingerprint(layer)==before.fingerprint
            manager.redo(); assert len(layer.paths)==count+2
            for actual,wanted in zip(layer.paths[-2:],paths):
                got=host.path_data(actual)
                for a,b in zip(got['nodes'],wanted['nodes']):
                    assert abs(a['x']-b['x'])<1e-7 and abs(a['y']-b['y'])<1e-7
            manager.undo()  # Keep the detached fixture small for the next case.
            cases+=1
        # A fractional crop exercises source-local offsets, independently of placement.
        image=host.new_image(path)
        image.transform=(1,0,0,1,0,0)
        iw,ih=image.image.size(); image.crop=NSMakeRect(iw*.05,ih*.05,iw*.9,ih*.9)
        crop=image_io.snapshot(image); data,_=image_io.prepare(crop,threading.Event())
        cropped=transform_paths(trace(TEST_ENGINE,data,{}),crop.geometry)
        for a,b in zip(tight_bounds(cropped),bounds): assert abs(a-b)<2,(name,a,b)
    # Background insertion uses the same image and never changes foreground paths.
    foreground=host.fingerprint(layer)
    apply_image(host,target(background),host.new_image(output/'plain.png'))
    snap=image_io.snapshot(background.backgroundImage); data,_=image_io.prepare(snap,threading.Event())
    paths=transform_paths(trace(TEST_ENGINE,data,{}),snap.geometry)
    apply_paths(host,target(background),paths)
    assert host.fingerprint(layer)==foreground
    manager.undo(); assert len(background.paths)==0
    manager.redo(); assert len(background.paths)==2
    from beztrace_companion.api import ImportRequest,prepare_imports,apply_imports
    host.fixture_font=font; host.fixture_owner=layer; host.fixture_background=background
    before=host.fingerprint(layer)
    job=prepare_imports(font,[ImportRequest(str(output/'dpi144.png'),'A',master.id,
                        preset='Custom',height=700,bottom=-120,horizontal=40,replace=True)],engine=TEST_ENGINE,_host=host)
    assert job._done.wait(30),'API preparation timed out'
    assert host.fingerprint(layer)==before
    report=apply_imports(job.plan,_host=host)
    assert report['completed']==1,report
    manager.undo(); assert host.fingerprint(layer)==before
    manager.redo()
    snap=image_io.snapshot(layer.backgroundImage); data,_=image_io.prepare(snap,threading.Event())
    bounds=tight_bounds(transform_paths(trace(TEST_ENGINE,data,{}),snap.geometry))
    for actual,wanted in zip(bounds,(40,-120,40+700*70/90,580)):
        # Horizontal ink aspect ratio follows tracing; vertical fit is exact.
        if wanted!=40+700*70/90: assert abs(actual-wanted)<1e-7,(actual,wanted)
    print('PASS native placement API: asynchronous read-only preparation, image-only apply, exact ink fit, Undo/Redo')
    acceptance = os.environ.get('BEZTRACE_ACCEPTANCE_IMAGE')
    if acceptance:
        image = host.new_image(Path(acceptance).resolve())
        image.transform = (1.25, .15, -.2, .9, 40.5, -120.25)
        apply_image(host, target(), image, replace=True)
        snap = image_io.snapshot(layer.backgroundImage)
        data, source_hash = image_io.prepare(snap, threading.Event())
        result = trace(TEST_ENGINE, data, {})
        assert trace(TEST_ENGINE, data, {}) == result
        (output/'acceptance-normalized.png').write_bytes(data)
        (output/'acceptance-result.json').write_text(json.dumps(result))
        placed = transform_paths(result, snap.geometry)
        before = host.fingerprint(layer)
        image_state = host.image_state(layer.backgroundImage)
        image_io.revalidate(host, target(), snap, source_hash)
        apply_paths(host, target(), placed)
        assert host.image_state(layer.backgroundImage) == image_state and layer.width == 0
        after = host.fingerprint(layer)
        manager.undo(); assert host.fingerprint(layer) == before
        manager.redo(); assert host.fingerprint(layer) == after
        print('PASS supplied image:', result['statistics'], 'source SHA256', source_hash,
              'native size', snap.geometry.size, 'affine placement/readback and Undo/Redo')
    print('PASS native canvas backend:' ,cases,'affine cases + crop/DPI/EXIF + foreground/background + image/path Undo/Redo; Glyphs',Glyphs.versionNumber,Glyphs.buildNumber)


if __name__=='__main__': run()
