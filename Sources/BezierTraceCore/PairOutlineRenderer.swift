// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import CoreGraphics
import ImageIO

public struct PairRenderedOutline: Sendable {
    public var image: MatchRasterInput
    public var pixelHeight: Int
    public var pixelWidth: Int
    public var unitsPerPixel: Double
    public var paddingPixels: Int
}

/// System-only, nonzero-fill raster rendering with an explicit inverse map.
/// No filesystem access or font metric normalization.
public enum PairOutlineRenderer {
    public static func render(_ master: MatchMaster, unitsPerEm: Double, pixelHeight: Int = 2048) throws -> PairRenderedOutline {
        guard (256...4096).contains(pixelHeight),!master.outline.contours.isEmpty else { throw MasterMatchError.invalid("render height must be 256...4096") }
        let rings=try master.outline.contours.map(MatchRing.init)
        for (i,r) in rings.enumerated() { try MatchGeometry.validate(r,unitsPerEm:unitsPerEm,context:.init(stage:"input",masterID:master.id,contour:i,existedBeforeFitting:true)) }
        let b=rings.dropFirst().reduce(rings[0].bounds) { $0.union($1.bounds) },pad=16
        let u=b.height/Double(pixelHeight-2*pad)
        guard u.isFinite,u>0 else { throw MasterMatchError.geometry("empty render bounds") }
        let required=ceil(b.width/u)+Double(2*pad)
        guard required.isFinite,required<=4096 else { throw MasterMatchError.invalid("render aspect ratio exceeds 4096px width") }
        let width=Int(required)
        guard width<=4096 else { throw MasterMatchError.invalid("render aspect ratio exceeds 4096px width") }
        guard let ctx=CGContext(data:nil,width:width,height:pixelHeight,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { throw MasterMatchError.geometry("render allocation") }
        ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:width,height:pixelHeight))
        let x=b.minX-Double(pad)*u,y=b.minY-Double(pad)*u
        // Quartz draws in y-up; PNG encoding establishes the display reflection.
        // Extraction returns y-up, then the explicit inverse map is applied once.
        ctx.scaleBy(x:1/u,y:1/u);ctx.translateBy(x:-x,y:-y)
        let path=CGMutablePath()
        for r in rings {
            path.move(to:CGPoint(x:r.spans[0].curve.start.x,y:r.spans[0].curve.start.y))
            for s in r.spans {
                let c=s.curve
                if s.line { path.addLine(to:CGPoint(x:c.end.x,y:c.end.y)) }
                else { path.addCurve(to:CGPoint(x:c.end.x,y:c.end.y),control1:CGPoint(x:c.control1.x,y:c.control1.y),control2:CGPoint(x:c.control2.x,y:c.control2.y)) }
            };path.closeSubpath()
        }
        ctx.addPath(path);ctx.setFillColor(CGColor(gray:0,alpha:1));ctx.drawPath(using:.fill)
        guard let cg=ctx.makeImage() else { throw MasterMatchError.geometry("render image") }
        let data=NSMutableData()
        guard let dest=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else { throw MasterMatchError.geometry("PNG encoder") }
        CGImageDestinationAddImage(dest,cg,nil)
        guard CGImageDestinationFinalize(dest) else { throw MasterMatchError.geometry("PNG encoding") }
        return .init(image:.init(id:master.id,imageData:data as Data,transform:[u*Double(pixelHeight)/1088,0,0,u*Double(pixelHeight)/1088,x,y]),pixelHeight:pixelHeight,pixelWidth:width,unitsPerPixel:u,paddingPixels:pad)
    }
}
