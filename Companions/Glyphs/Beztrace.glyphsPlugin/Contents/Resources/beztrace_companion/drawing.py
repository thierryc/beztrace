# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Cached AppKit rendering. No Glyphs or filesystem access during drawing."""
import math
from AppKit import (NSBezierPath, NSColor, NSFont, NSGraphicsContext,
    NSNonZeroWindingRule, NSCompositingOperationSourceOver,
    NSFontAttributeName, NSForegroundColorAttributeName)
from Foundation import NSString

LABELS = dict(baseline='Baseline', capHeight='Cap height', xHeight='x-height',
              ascender='Ascender', descender='Descender')


class CachedDrawing:
    def __init__(self, geometry, image):
        self.geometry = geometry
        self.image = image
        self.path = NSBezierPath.bezierPath()
        self.path.setWindingRule_(NSNonZeroWindingRule)
        for kind, values in geometry.commands:
            if kind == 'M':
                self.path.moveToPoint_(values)
            elif kind == 'L':
                self.path.lineToPoint_(values)
            elif kind == 'C':
                self.path.curveToPoint_controlPoint1_controlPoint2_(values[4:6], values[:2], values[2:4])
            else:
                self.path.closePath()
        lo, _, hi, _ = geometry.ink_bounds
        self.guides = []
        for key, y in geometry.guides:
            guide = NSBezierPath.bezierPath()
            guide.moveToPoint_((min(0, lo)-60, y))
            guide.lineToPoint_((max(hi, 0)+120, y))
            self.guides.append((key, y, guide))

    def draw(self, scale=1.0, source=False, outlines=True, guides=True):
        scale = float(scale)
        if not math.isfinite(scale) or scale <= 0:
            return
        scale = max(scale, .01)
        NSGraphicsContext.saveGraphicsState()
        try:
            if source and self.image is not None:
                x0, y0, x1, y1 = self.geometry.image_bounds
                self.image.drawInRect_fromRect_operation_fraction_(
                    ((x0,y0),(x1-x0,y1-y0)), ((0,0),(0,0)), NSCompositingOperationSourceOver, .28 if outlines else 1)
            if outlines:
                accent = NSColor.controlAccentColor()
                accent.colorWithAlphaComponent_(.16).set()
                self.path.fill()
                accent.set()
                self.path.setLineWidth_(1.4/scale)
                self.path.stroke()
            if guides:
                NSColor.secondaryLabelColor().colorWithAlphaComponent_(.65).set()
                attrs = {NSFontAttributeName: NSFont.systemFontOfSize_(10/scale),
                         NSForegroundColorAttributeName: NSColor.secondaryLabelColor()}
                for key, y, guide in self.guides:
                    guide.setLineWidth_(.7/scale)
                    if key == 'baseline':
                        guide.setLineDash_count_phase_([],0,0)
                    else:
                        guide.setLineDash_count_phase_([4/scale,3/scale],2,0)
                    guide.stroke()
                    label = '%s · %g' % (LABELS[key],y)
                    NSString.stringWithString_(label).drawAtPoint_withAttributes_(
                        (max(self.geometry.ink_bounds[2],0)+8/scale,y+3/scale),attrs)
        finally:
            NSGraphicsContext.restoreGraphicsState()
