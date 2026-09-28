# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Image-local to canvas geometry. No Glyphs or AppKit dependencies."""
import copy
from dataclasses import dataclass
from .contract import CompanionError, number


@dataclass(frozen=True)
class ImageGeometry:
    size: tuple
    crop: tuple  # x, y, width, height in native image-local coordinates
    transform: tuple  # a, b, c, d, tx, ty

    def validate(self):
        if len(self.size)!=2 or len(self.crop)!=4 or len(self.transform)!=6:
            raise CompanionError('Invalid native image geometry')
        if not all(number(v) and abs(v)<=1e9 for v in self.size+self.crop+self.transform):
            raise CompanionError('Image placement contains invalid coordinates')
        w,h=self.size; x,y,cw,ch=self.crop
        a,b,c,d,_,_=self.transform
        if min(w,h,cw,ch)<=0 or abs(a*d-b*c)<1e-12:
            raise CompanionError('Image size, crop, or transform is empty or singular')
        if x<0 or y<0 or x+cw>w+1e-7 or y+ch>h+1e-7:
            raise CompanionError('Image crop extends outside the image. Reset its crop in Glyphs.')
        return self


def transform_paths(result, geometry):
    """Map the complete cropped raster canvas, never the traced ink bounds."""
    geometry.validate()
    if result.get('placement') is not None:
        raise CompanionError('Expected neutral tracing coordinates')
    x,y,w,h=geometry.crop
    source=result['source']; a,b,c,d,tx,ty=geometry.transform
    sx=w/(1088.0*source['width']/source['height']); sy=h/1088.0
    paths=copy.deepcopy(result['paths'])
    for path in paths:
        for node in path['nodes']:
            px=x+node['x']*sx; py=y+node['y']*sy
            node['x'],node['y']=a*px+c*py+tx,b*px+d*py+ty
            if not all(number(node[k]) and abs(node[k])<=1e9 for k in ('x','y')):
                raise CompanionError('Transformed outline exceeds coordinate limits')
    return paths


def fitted_transform(result, size, fit, horizontal=0):
    """Place native image so its ink has the requested range (agent API only)."""
    if not number(horizontal): raise CompanionError('Invalid horizontal position')
    x0,y0,x1,y1=result['bounds']
    if y1<=y0: raise CompanionError('Image has no measurable ink height')
    width,height=size
    ImageGeometry(tuple(size),(0.,0.,width,height),(1.,0.,0.,1.,0.,0.)).validate()
    scale=fit.height/(y1-y0)
    # Neutral canvas is 1088 high; account for native logical size and DPI.
    uniform=scale*1088/height
    native_x0=x0*width/(1088*result['source']['width']/result['source']['height'])
    return (uniform,0.,0.,uniform,horizontal-uniform*native_x0,fit.bottom-scale*y0)
