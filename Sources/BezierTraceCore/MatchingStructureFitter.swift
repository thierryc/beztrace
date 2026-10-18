// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Fixed segment fitting shared by vector and raster matching.
import Foundation

enum MatchingStructureFitter {
    static func fitVector(_ target: MatchRing,to reference: MatchRing,contour: Int,tolerance: Double) throws -> MatchRing {
        var points:[Point2D]=[],roles:[Int]=[]
        for i in target.spans.indices {
            let span=target.spans[i]
            let flat=try PairGeometry.flatten(MatchRing(spans:[span]),epsilon:tolerance/200)
            for (index,p) in flat.dropLast().enumerated() {
                points.append(p);roles.append(index==0 ? OutlineMatcher.signature(target,i) : 0)
            }
        }
        let boundary=MatchRing(spans:points.indices.map { i in
            .init(curve:lineCubic(from:points[i],to:points[(i+1)%points.count]),line:true,
                  startSource:nil,controlSources:[nil,nil],smooth:abs(roles[i]) != 1,featureRole:roles[i])
        })
        let map=OutlineMatcher.anchors(reference,boundary),cuts=reference.fractions()+[1]
        var targetCuts=cuts.map { OutlineMatcher.warp($0,map) }
        optimizeTargetCuts(reference:reference,target:boundary,cuts:cuts,targetCuts:&targetCuts,
            mode:.traceToReference,policy:.fixed,tolerance:tolerance,map:map,refine:true,coupledSearch:true)
        let sections=refineFixedSections(reference:reference,target:boundary,cuts:cuts,targetCuts:targetCuts,mode:.traceToReference,tolerance:tolerance)
        if let index=sections.indices.first(where:{ !sections[$0].accepted }) {
            throw MasterMatchError.fitDiagnostic(.init(code:"fixed-structure-fit",
                message:"Vector contour \(contour), section \(index): \(sections[index].reason)",
                stage:"fitting",role:"target",locations:[.init(contour:contour,segment:index,
                    startNode:reference.spans[index].startSource,endNode:reference.spans[(index+1)%reference.spans.count].startSource,parameterRange:[0,1])],
                existedBeforeFitting:false,section:index,measuredDeviation:sections[index].error,
                allowedDeviation:tolerance*(15.0/16),cause:"fit-not-established"))
        }
        var fitted=MatchRing(spans:sections.map(\.b),prefix:reference.prefix)
        if fitted.bounds.minY<target.bounds.minY || fitted.bounds.maxY>target.bounds.maxY {
            let adjusted=try PairEnvelopeFitter.fit(Outline(contours:[fitted.serialized().0]),
                source:Outline(contours:[target.serialized().0]),bounds:target.bounds,tolerance:tolerance)
            fitted=try MatchRing(adjusted.contours[0])
        }
        guard try PairGeometry.measure(target,fitted,tolerance:tolerance).upperBound<=tolerance else {
            throw MasterMatchError.fit(contour,"vector boundary refinement did not establish full-source tolerance")
        }
        return fitted
    }
    struct FittedSection {
        var a: MatchSpan
        var b: MatchSpan
        var error: Double
        var accepted: Bool
        var score: Double
        var reason: String
    }

    static func samples(_ ring: MatchRing, start: Double, end: Double) -> [Point2D] {
        let fractions = ring.fractions()
        var result = [ring.point(start)]
        result += fractions.enumerated().filter { $0.element>start+1e-8 && $0.element<end-1e-8 }.map { ring.spans[$0.offset].curve.start }
        result.append(ring.point(end)); return result
    }

    static func section(reference r: MatchRing,target t: MatchRing,start: Double,end: Double,
                                targetStart ts: Double,targetEnd te: Double,mode: RasterMatchMode,
                                policy: ReferencePolicy,tolerance: Double,refine: Bool = false,
                                targetStartPoint: Point2D? = nil,targetEndPoint: Point2D? = nil,
                                coupled: Bool = true) -> FittedSection {
        let exact = mode == .traceToReference ? r.subspan(start,end) : nil
        var a = exact ?? fitted(r,start:start,end:end,tolerance:tolerance)
        var b = fitted(t,start:ts,end:te,tolerance:tolerance,refine:refine,startPoint:targetStartPoint,endPoint:targetEndPoint,coupled:coupled)
        if policy == .fixed {
            if a.line { b.curve=lineCubic(from:b.curve.start,to:b.curve.end); b.line=true }
            else { b.line=false }
        } else if !a.line || !b.line { a.line=false; b.line=false }
        let error=max(mode == .traceToReference ? 0 : sectionDeviation(a,boundary:r,start:start,end:end),
                      sectionDeviation(b,boundary:t,start:ts,end:te))
        let tf=t.fractions()
        let rf=r.fractions()
        let corner=t.spans.indices.contains { abs(OutlineMatcher.signature(t,$0))==1 && tf[$0]>ts+1e-7 && tf[$0]<te-1e-7 }
            || (mode == .traceBoth && r.spans.indices.contains { abs(OutlineMatcher.signature(r,$0))==1 && rf[$0]>start+1e-7 && rf[$0]<end-1e-7 })
        let safe=(a.line || MatchGeometry.controlled(a.curve)) && (b.line || MatchGeometry.controlled(b.curve)) &&
            (a.line || (0...100).allSatisfy { i in
                let f=Double(i)/100
                return MatchGeometry.controlled(CubicBezier(start:a.curve.start.interpolated(to:b.curve.start,t:f),
                    control1:a.curve.control1.interpolated(to:b.curve.control1,t:f),
                    control2:a.curve.control2.interpolated(to:b.curve.control2,t:f),end:a.curve.end.interpolated(to:b.curve.end,t:f)))
            })
        let validReference = mode != .traceToReference || exact != nil
        var reasons: [String]=[]
        if !validReference { reasons.append("original reference knot cannot be crossed") }
        if corner { reasons.append("intentional target corner requires correspondence") }
        if !safe { reasons.append("handle or sampled interpolation safety check failed") }
        if error>tolerance*(15.0/16) { reasons.append("measured section deviation \(error) exceeds fitting budget \(tolerance*(15.0/16))") }
        return .init(a:a,b:b,error:error,accepted:validReference && !corner && safe && error<=tolerance*(15.0/16),
            score:error + (corner ? 1e6 : 0) + (safe && validReference ? 0 : 1e6),reason:reasons.joined(separator:"; "))
    }

    static func refineFixedSections(reference r: MatchRing,target t: MatchRing,cuts: [Double],
        targetCuts: [Double],mode: RasterMatchMode,tolerance: Double) -> [FittedSection] {
        let count=cuts.count-1, original=targetCuts.dropLast().map { t.point($0) }
        var knots=original
        func fitted(_ index: Int,_ points: [Point2D]) -> FittedSection {
            section(reference:r,target:t,start:cuts[index],end:cuts[index+1],
                targetStart:targetCuts[index],targetEnd:targetCuts[index+1],mode:mode,policy:.fixed,
                tolerance:tolerance,refine:true,targetStartPoint:points[index],targetEndPoint:points[(index+1)%count])
        }
        var result=(0..<count).map { fitted($0,knots) }
        let movementLimit=t.spans.reduce(0.0) { $0+$1.curve.start.matchDistance(to:$1.curve.end) }/64+tolerance
        func consider(_ candidate: [Point2D],_ affected: [Int]) -> Bool {
            for j in affected {
                guard candidate[j].matchDistance(to:original[j])<=movementLimit else { return false }
                let previous=(j+count-1)%count
                let local=samples(t,start:targetCuts[previous],end:targetCuts[previous+1])
                    + samples(t,start:targetCuts[j],end:targetCuts[j+1])
                guard MatchGeometry.distance(candidate[j],to:local)<=tolerance else { return false }
            }
            let proposed=affected.map { fitted($0,candidate) }
            func score(_ values: [FittedSection]) -> Double {
                (values.map(\.score).max() ?? 0)+values.reduce(0) { $0+$1.error }*0.05
            }
            if score(proposed)<score(affected.map { result[$0] })-1e-6 {
                knots=candidate
                for (j,section) in zip(affected,proposed) { result[j]=section }
                return true
            }
            return false
        }
        for pass in 0..<12 {
            var changed=false
            for i in 0..<count where result[i].a.line && !result[i].accepted {
                let next=(i+1)%count, previous=(i+count-1)%count
                let affected=Array(Set([previous,i,next])).sorted()
                if let fit=MatchingLineFitter.fit(samples(t,start:targetCuts[i],end:targetCuts[i+1])) {
                    for fraction in [1.0,0.5,0.25] {
                        var candidate=knots
                        candidate[i]=knots[i].interpolated(to:fit.curve.start,t:fraction)
                        candidate[next]=knots[next].interpolated(to:fit.curve.end,t:fraction)
                        if consider(candidate,affected) { changed=true }
                    }
                }
                let chord=knots[next]-knots[i]
                guard let direction=chord.matchNormalized() else { continue }
                let normal=Vector2D(dx:-direction.dy,dy:direction.dx)
                let values=samples(t,start:targetCuts[i],end:targetCuts[i+1]).map { ($0-knots[i]).dot(normal) }
                let offset=((values.min() ?? 0)+(values.max() ?? 0))/2
                for fraction in [1.0,0.5,0.25] {
                    var candidate=knots
                    candidate[i]=knots[i]+normal*(offset*fraction)
                    candidate[next]=knots[next]+normal*(offset*fraction)
                    if consider(candidate,affected) { changed=true }
                }
                // Neighboring line constraints often need an apex to move
                // along both normals together rather than shift one whole line.
                let step=tolerance*pow(0.5,Double(pass/3))
                for j in [i,next] {
                    let indices=Array(Set([(j+count-1)%count,j])).sorted()
                    for (x,y) in [(1.0,0.0),(-1.0,0.0),(0.0,1.0),(0.0,-1.0),
                                  (1.0,1.0),(1.0,-1.0),(-1.0,1.0),(-1.0,-1.0)] {
                        var candidate=knots
                        candidate[j]=knots[j]+Vector2D(dx:x*step,dy:y*step)
                        if consider(candidate,indices) { changed=true }
                    }
                }
            }
            if result.allSatisfy(\.accepted) { break }
            if !changed && pass>=9 { break }
        }
        return result
    }

    static func optimizeTargetCuts(reference r: MatchRing,target t: MatchRing,cuts: [Double],
        targetCuts: inout [Double],mode: RasterMatchMode,policy: ReferencePolicy,tolerance: Double,map: [(Double,Double)],refine: Bool = false,coupledSearch: Bool = false) {
        guard cuts.count>3 else { return }
        var locked=Array(repeating:false,count:cuts.count); locked[0]=true; locked[cuts.count-1]=true
        let tf=t.fractions(), corners=t.spans.indices.filter { abs(OutlineMatcher.signature(t,$0))==1 }.map { tf[$0] }
        // Match genuine corners to existing free knots before asking for a new
        // knot. Keep cyclic order and already aligned corner correspondences.
        for i in 1..<(cuts.count-1) {
            locked[i]=corners.contains { abs($0-targetCuts[i])<1e-7 }
            if let anchor=map.first(where:{ abs($0.0-cuts[i])<1e-7 && abs($0.1-targetCuts[i])<1e-7 }) {
                let (ri,rt)=r.location(anchor.0), (ti,tt)=t.location(anchor.1)
                if rt<1e-7 && tt<1e-7 {
                    let role=OutlineMatcher.signature(r,ri)
                    // Paired corners, extrema and transitions keep their
                    // correspondence; only unassigned fitting knots slide.
                    if role != 0 && role==OutlineMatcher.signature(t,ti) { locked[i]=true }
                }
            }
        }
        for corner in corners where corner>1e-7 && corner<1-1e-7 && !targetCuts.contains(where:{ abs($0-corner)<1e-7 }) {
            let indices=(1..<(cuts.count-1)).filter { !locked[$0] && corner>targetCuts[$0-1]+1e-7 && corner<targetCuts[$0+1]-1e-7 }
            if let i=indices.min(by:{ abs(targetCuts[$0]-corner)<abs(targetCuts[$1]-corner) }) { targetCuts[i]=corner; locked[i]=true }
        }
        func score(_ i: Int,_ value: Double) -> Double {
            // Correspondence search uses the economical fit. Coupled minimax
            // runs after span assignment, rather than at every trial cut.
            let a=section(reference:r,target:t,start:cuts[i-1],end:cuts[i],targetStart:targetCuts[i-1],targetEnd:value,mode:mode,policy:policy,tolerance:tolerance,refine:refine,coupled:coupledSearch)
            let b=section(reference:r,target:t,start:cuts[i],end:cuts[i+1],targetStart:value,targetEnd:targetCuts[i+1],mode:mode,policy:policy,tolerance:tolerance,refine:refine,coupled:coupledSearch)
            return max(a.score,b.score)+(a.error+b.error)*0.05
        }
        for _ in 0..<(refine ? 16 : 3) {
            var changed=false
            for i in 1..<(cuts.count-1) where !locked[i] {
                let aligned=OutlineMatcher.warp(cuts[i],map)
                let (sourceIndex,sourceParameter)=r.location(cuts[i])
                let previous=(sourceIndex+r.spans.count-1)%r.spans.count
                // A smooth line/curve transition is a structural landmark.
                // A thicker rounded foot can move its tangent location even
                // when the coarse geometric map remains almost the identity.
                // Use the existing feature-anchor window for that transition;
                // other free knots retain the two-sample fitting neighborhood.
                let transition=refine && sourceParameter<1e-7 && r.spans[sourceIndex].smooth
                    && r.spans[sourceIndex].line != r.spans[previous].line
                let radius=transition ? MatchCorrespondence.landmarkWindow : 1.0/64
                let current=targetCuts[i], lo=max(targetCuts[i-1]+1e-7,aligned-radius),
                    hi=min(targetCuts[i+1]-1e-7,aligned+radius)
                var best=current, value=score(i,current)
                for candidate in [current-(current-lo)*0.2,current+(hi-current)*0.2,
                                  current-(current-lo)*0.4,current+(hi-current)*0.4,
                                  current-(current-lo)*0.05,current+(hi-current)*0.05] {
                    // Fitting error must not buy an unrelated correspondence.
                    // Slide at most two shape-alignment samples from its map.
                    guard candidate>targetCuts[i-1]+1e-7, candidate<targetCuts[i+1]-1e-7,
                          abs(candidate-aligned)<=radius else { continue }
                    let next=score(i,candidate)
                    if next<value-1e-6 { best=candidate; value=next }
                }
                if best != current { targetCuts[i]=best; changed=true }
            }
            if !changed { break }
        }
    }

    static func fitted(_ ring: MatchRing, start: Double, end: Double, tolerance: Double, refine: Bool = false,
                               startPoint: Point2D? = nil,endPoint: Point2D? = nil,coupled: Bool = true) -> MatchSpan {
        let boundaryPoints = samples(ring,start:start,end:end)
        var points=boundaryPoints
        if let startPoint { points[0]=startPoint }
        if let endPoint { points[points.count-1]=endPoint }
        let straight = ContourPlanner.chordDeviation(points) <= tolerance/8
        let (index,local) = ring.location(start)
        let corner = local < 1e-7 && abs(OutlineMatcher.signature(ring,index)) == 1
        func tangent(_ fraction: Double, outgoing: Bool) -> Vector2D {
            // A marching-squares edge is a pixel-scale direction, not a curve
            // tangent. Estimate over a bounded physical neighbourhood instead
            // of fitting its staircase. Wrap at the cyclic start; corners use
            // the corresponding one-sided neighbourhood and remain corners.
            let length = ring.spans.reduce(0.0) { $0+$1.curve.start.matchDistance(to:$1.curve.end) }
            let delta = min((end-start)/4,max(0.001,4*tolerance/max(length,1e-12)))
            func periodic(_ f: Double) -> Point2D {
                ring.point(f < 0 ? f+1 : f > 1 ? f-1 : f)
            }
            let a = periodic(fraction-delta), b = periodic(fraction+delta)
            let one = outgoing ? periodic(fraction+delta)-periodic(fraction)
                : periodic(fraction)-periodic(fraction-delta)
            let (i,t) = ring.location(fraction)
            let atCorner = t < 1e-7 && abs(OutlineMatcher.signature(ring,i)) == 1
            return (atCorner ? one : b-a).matchNormalized() ?? Vector2D(dx:1,dy:0)
        }
        if refine && !straight,let result=HybridCubicFitter.fit(polyline:boundaryPoints,tolerance:tolerance,
            start:points[0],end:points.last!,startTangent:tangent(start,outgoing:true),endTangent:tangent(end,outgoing:false)) {
            return MatchSpan(curve:result.curve,line:false,startSource:nil,controlSources:[nil,nil],smooth:!corner)
        }
        var curve = straight ? lineCubic(from:points[0],to:points.last!) : ContourFitter.constrainedCubicFit(
            samples:points,startTangent:tangent(start,outgoing:true),endTangent:-tangent(end,outgoing:false),deterministicLengths:true).curve
        if !straight {
            let free=MatchingCubicFitter.fit(points)
            func error(_ c: CubicBezier) -> Double {
                let poly=(0...64).map { c.point(at:Double($0)/64) }
                return max(boundaryPoints.map { MatchGeometry.distance($0,to:poly) }.max() ?? 0,
                           poly.map { MatchGeometry.distance($0,to:boundaryPoints) }.max() ?? 0)
            }
            if MatchGeometry.controlled(free) && (!MatchGeometry.controlled(curve) || error(free)<error(curve)) { curve=free }
            if refine && error(curve)>tolerance*(15.0/16) {
                let candidates=[
                    MatchingCubicFitter.fit(points,refinementBudget:tolerance*(15.0/16),
                        startTangent:tangent(start,outgoing:true),endTangent:-tangent(end,outgoing:false)),
                    MatchingCubicFitter.fit(points,refinementBudget:tolerance*(15.0/16))]
                for candidate in candidates where MatchGeometry.controlled(candidate) && error(candidate)<error(curve) { curve=candidate }
            }
            if refine && error(curve)>tolerance*(15.0/16) {
                // Least squares minimizes mean error; acceptance bounds the maximum.
                curve=MatchingCubicFitter.polish(curve,points:boundaryPoints,budget:tolerance*(15.0/16))
            }
            if refine && coupled && error(curve)>tolerance*(15.0/16) {
                curve=MatchingCubicFitter.minimax(curve,points:boundaryPoints,budget:tolerance*(15.0/16))
            }
        }
        return MatchSpan(curve:curve,line:straight,startSource:nil,controlSources:[nil,nil],smooth:!corner)
    }

    static func sectionDeviation(_ span: MatchSpan, boundary: MatchRing, start: Double, end: Double) -> Double {
        let p = samples(boundary,start:start,end:end)
        let q = (0...64).map { span.curve.point(at:Double($0)/64) }
        return max(p.map { MatchGeometry.distance($0,to:q) }.max() ?? 0,q.map { MatchGeometry.distance($0,to:p) }.max() ?? 0)
    }
}
