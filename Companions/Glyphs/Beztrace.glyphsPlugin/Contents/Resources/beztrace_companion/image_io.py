# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Native image snapshots and bounded worker-side raster preparation."""
import hashlib
import math
from dataclasses import dataclass
from pathlib import Path
from .contract import CompanionError, MAX_INPUT
from .canvas import ImageGeometry


def read_source(path):
    path=Path(path)
    if path.suffix.lower() not in ('.png','.jpg','.jpeg'):
        raise CompanionError('Choose a PNG or JPEG image')
    with path.open('rb') as stream: data=stream.read(MAX_INPUT+1)
    if not data or len(data)>MAX_INPUT: raise CompanionError('Image must contain 1 byte to 16 MiB')
    return data


def digest(data): return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class ImageSnapshot:
    path: str
    image: object  # Detached NSImage copy, never a Glyphs object
    geometry: ImageGeometry
    identity: object
    file_state: tuple


def file_state(path):
    stat=Path(path).stat()
    return stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns,stat.st_ctime_ns


def native_geometry(image):
    size=image.image.size(); crop=image.crop
    return ImageGeometry((float(size.width),float(size.height)),
        (float(crop.origin.x),float(crop.origin.y),float(crop.size.width),float(crop.size.height)),
        tuple(float(v) for v in image.transform)).validate()


def snapshot(image):
    if image is None: raise CompanionError('Choose an image or place one on this layer in Glyphs')
    if image.image is None: raise CompanionError('The canvas image cannot be loaded')
    path=str(image.path)
    return ImageSnapshot(path,image.image.copy(),native_geometry(image),image,file_state(path))


def prepare(snapshot, cancel):
    """Render the native image crop without its display opacity or canvas transform.

    AppKit bitmap contexts are local to this worker. Using the native NSImage
    rendering preserves the same orientation and logical image size as Glyphs.
    """
    from AppKit import (NSBitmapImageRep, NSGraphicsContext, NSDeviceRGBColorSpace,
        NSCompositingOperationCopy, NSBitmapImageFileTypePNG)
    from Foundation import NSAutoreleasePool, NSData
    from Quartz import (CGImageSourceCreateWithData, CGImageSourceCopyPropertiesAtIndex, CGImageSourceGetType,
                        kCGImagePropertyPixelWidth,kCGImagePropertyPixelHeight)
    from .engine import Cancelled
    if cancel.is_set(): raise Cancelled('Cancelled')
    pool=NSAutoreleasePool.alloc().init()
    try:
        original=read_source(snapshot.path)
        if file_state(snapshot.path)!=snapshot.file_state: raise CompanionError('Source image changed; trace again')
        src=CGImageSourceCreateWithData(NSData.dataWithBytes_length_(original,len(original)),None)
        if src is None or str(CGImageSourceGetType(src)) not in ('public.png','public.jpeg'):
            raise CompanionError('Source image must be PNG or JPEG')
        props=CGImageSourceCopyPropertiesAtIndex(src,0,None) if src else None
        if not props: raise CompanionError('Cannot decode source image')
        pw,ph=int(props[kCGImagePropertyPixelWidth]),int(props[kCGImagePropertyPixelHeight])
        if min(pw,ph)<1 or max(pw,ph)>4096: raise CompanionError('Image dimensions must not exceed 4096 × 4096')
        # Native TIFF representation has the orientation used by NSImage, and its
        # bitmap dimensions avoid assuming a relationship between points and pixels.
        tiff=snapshot.image.TIFFRepresentation()
        rep=NSBitmapImageRep.imageRepWithData_(tiff)
        if rep is None: raise CompanionError('Cannot snapshot the canvas image')
        iw,ih=snapshot.geometry.size; x,y,cw,ch=snapshot.geometry.crop
        w=max(1,int(math.ceil(rep.pixelsWide()*cw/iw)))
        h=max(1,int(math.ceil(rep.pixelsHigh()*ch/ih)))
        if max(w,h)>4096: raise CompanionError('Canvas image raster exceeds 4096 × 4096')
        bitmap=NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
            None,w,h,8,4,True,False,NSDeviceRGBColorSpace,0,0)
        bitmap.setSize_((w,h))
        context=NSGraphicsContext.graphicsContextWithBitmapImageRep_(bitmap)
        NSGraphicsContext.saveGraphicsState()
        try:
            NSGraphicsContext.setCurrentContext_(context)
            snapshot.image.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
                ((0,0),(w,h)),((x,y),(cw,ch)),NSCompositingOperationCopy,1.0,False,None)
        finally: NSGraphicsContext.restoreGraphicsState()
        data=bytes(bitmap.representationUsingType_properties_(NSBitmapImageFileTypePNG,{}))
        if not data or len(data)>MAX_INPUT: raise CompanionError('Prepared image exceeds the engine input limit')
        if cancel.is_set(): raise Cancelled('Cancelled')
        return data,digest(original)
    finally:
        del pool


def revalidate(host, target, image, source_hash):
    current=target.layer.backgroundImage
    if (current is None or not host.same(current,image.identity) or str(current.path)!=image.path
            or native_geometry(current)!=image.geometry or file_state(image.path)!=image.file_state
            or digest(read_source(image.path))!=source_hash):
        raise CompanionError('The canvas image changed. Trace again at its new placement.')
