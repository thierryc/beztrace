#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Compare joint tracing with pinned Noto Sans variable-font instances.

Test-only Pillow/fontTools dependencies; no product runtime dependency. Artifacts
are confined to a new .build directory. This does not qualify native Glyphs HOI.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image,ImageDraw,ImageFont,ImageChops
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT=Path(__file__).resolve().parents[1]


def render(font_source,weight,glyph,directory):
    font=instantiateVariableFont(TTFont(font_source),{'wght':weight,'wdth':100},inplace=False)
    path=directory/('noto-'+str(weight)+'.ttf'); font.save(path)
    image=Image.new('L',(1024,1024),255)
    ImageDraw.Draw(image).text((100,900),glyph,font=ImageFont.truetype(str(path),1024),fill=0,anchor='ls')
    target=directory/(glyph+'-'+str(weight)+'.png'); image.save(target)
    return target,image


def interpolate(a,b,t):
    return [dict(closed=True,nodes=[dict(n,x=n['x']+(m['x']-n['x'])*t,y=n['y']+(m['y']-n['y'])*t)
            for n,m in zip(p['nodes'],q['nodes'])]) for p,q in zip(a,b)]


def raster(paths):
    # Standalone reconstruction at the same canvas placement, including counters.
    sys_path=ROOT/'Companions/Glyphs/Beztrace.glyphsPlugin/Contents/Resources'
    import sys
    sys.path.insert(0,str(sys_path))
    from beztrace_companion.contract import segments,signed_area
    image=Image.new('L',(1024,1024),255); draw=ImageDraw.Draw(image)
    largest=max(paths,key=lambda p:abs(signed_area(p))); sign=1 if signed_area(largest)>0 else -1
    for path in sorted(paths,key=lambda p:-abs(signed_area(p))):
        points=[]
        for start,controls,end in segments(path):
            ps=[start]+controls+[end]
            for k in range(65):
                t=k/64; u=1-t
                weights=[u,t] if not controls else [u**3,3*u*u*t,3*u*t*t,t**3]
                x,y=[sum(w*p[axis] for w,p in zip(weights,ps)) for axis in ('x','y')]
                points.append((100+x*1.024,900-y*1.024))
        draw.polygon(points,fill=0 if signed_area(path)*sign>0 else 255)
    return image


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine',type=Path,default=ROOT/'.build/beztrace-0.2.0-dev.1-package/bin/beztrace')
    parser.add_argument('--output',type=Path,default=ROOT/'.build/raster-variable-qualification')
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=False)
    source=ROOT/'Tests/Fixtures/sources/noto-sans/NotoSans[wdth,wght].ttf'
    report=dict(sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),engine=str(args.engine.resolve()),
                axis=dict(tag='wght',locations=[400,800],fixedWidth=100),sampledOnly=True,nativeHOIVerified=False,cases=[])
    for glyph in ('O','H'):
        inputs=[]; images={}
        for weight in (400,500,600,700,800):
            path,image=render(source,weight,glyph,args.output); images[weight]=image
            if weight in (400,800):
                inputs.append(dict(id=str(weight),imageData=base64.b64encode(path.read_bytes()).decode(),
                    transform=[1000/1088,0,0,1000/1088,-100/1.024,-124/1.024]))
        request=dict(schemaVersion=1,mode='trace-both',unitsPerEm=1000,axis=dict(tag='wght',locations=[400,800]),
            images=inputs,options=dict(referencePolicy='shared-subdivision',fitTolerance=1,contourPairs=[],startNodes=[]),
            rasterOptions=dict(threshold=None,invert=False,minimumContourArea=100,smoothing=1,cornerThresholdDegrees=12))
        data=json.dumps(request,separators=(',',':')).encode()
        process=subprocess.run([str(args.engine),'match','-','--json-errors'],input=data,capture_output=True,timeout=30)
        case=dict(glyph=glyph,status='failed',samples=[])
        if process.returncode:
            case['error']=process.stderr.decode(); report['cases'].append(case); continue
        result=json.loads(process.stdout); (args.output/(glyph+'-master-set.json')).write_bytes(process.stdout)
        case.update(status='passed',endpointDeviations=[r['maximumBoundaryDeviation'] for r in result['rasterSources']])
        for weight in (400,500,600,700,800):
            predicted=raster(interpolate(result['reference']['outline']['contours'],result['target']['outline']['contours'],(weight-400)/400))
            predicted.save(args.output/(glyph+'-'+str(weight)+'-matched.png'))
            # Pixel disagreement is reported, not confused with fitting error or
            # a guarantee that the source font itself interpolates linearly.
            actual=images[weight].point(lambda p:0 if p<128 else 255)
            difference=ImageChops.difference(actual,predicted); hist=difference.histogram()
            area=actual.histogram()[0]
            case['samples'].append(dict(weight=weight,differentPixels=hist[255],relativeInkDifference=hist[255]/max(1,area)))
        report['cases'].append(case)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report,indent=2))
    return 0 if all(c['status']=='passed' and max(c['endpointDeviations'])<=1 for c in report['cases']) else 1


if __name__=='__main__': raise SystemExit(main())
