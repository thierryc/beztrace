# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Detached canvas crop exchange; native capture belongs to the main thread."""
import base64
import struct
from .contract import CompanionError
from . import image_io


def descriptor(data,snapshot,master_id):
    if data[:8]!=b'\x89PNG\r\n\x1a\n' or len(data)<24:
        raise CompanionError('Prepared canvas crop is not a PNG')
    width,height=struct.unpack('>II',data[16:24])
    if not 1<=min(width,height)<=max(width,height)<=4096:
        raise CompanionError('Prepared canvas crop dimensions exceed limits')
    geometry=snapshot.geometry.validate()
    x,y,w,h=geometry.crop; a,b,c,d,tx,ty=geometry.transform
    sx=w/(1088.*width/height); sy=h/1088.
    return dict(id=str(master_id),imageData=base64.b64encode(data).decode('ascii'),
                transform=[a*sx,b*sx,c*sy,d*sy,a*x+c*y+tx,b*x+d*y+ty])


def capture(ctx,mode):
    indices=[1] if mode==1 else [0,1]
    return [(i,image_io.snapshot(ctx['targets'][i].layer.backgroundImage)) for i in indices]


def prepare_sources(ctx,sources,cancel):
    images=[]; evidence=[]
    for index,snapshot in sources:
        data,source_hash=image_io.prepare(snapshot,cancel)
        images.append(descriptor(data,snapshot,ctx['targets'][index].owner.layerId))
        evidence.append((index,snapshot,source_hash))
    # No Glyphs reads here; publish detached data before the main-thread phase.
    ctx['source_evidence']=evidence
    return images


def revalidate_sources(host,ctx):
    for index,snapshot,source_hash in ctx.get('source_evidence',()):
        image_io.revalidate(host,ctx['targets'][index],snapshot,source_hash)
