// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import CryptoKit

public enum PairMatcher {
    static func rank(_ accepted: [PairCandidateReport],routes: [String]) -> (reports:[PairCandidateReport],tiedCount:Int) {
        // Keep only candidates whose fidelity interval overlaps the best upper
        // bound. Economy and smooth joins break measurement-level ties.
        let bestUpper=accepted.map { $0.sourceDeviations.map(\.upperBound).max() ?? 0 }.min()
        let tied=accepted.filter { ($0.sourceDeviations.map(\.lowerBound).max() ?? 0) <= (bestUpper ?? 0) }
        let ranked=tied.sorted {
            if $0.totalNodes != $1.totalNodes { return $0.totalNodes! < $1.totalNodes! }
            if $0.onCurveNodes != $1.onCurveNodes { return $0.onCurveNodes! < $1.onCurveNodes! }
            if $0.excessSmoothJoinResidual != $1.excessSmoothJoinResidual { return $0.excessSmoothJoinResidual! < $1.excessSmoothJoinResidual! }
            return routes.firstIndex(of:$0.route)! < routes.firstIndex(of:$1.route)!
        }
        return (ranked,tied.count)
    }
    public static func match(reference: PairInput,target: PairInput,unitsPerEm: Double,axis: MatchAxis,
                             options: MasterMatchOptions,strategy: PairStrategy = .direct,
                             rasterOptions: RasterMatchOptions = .init(),renderHeight: Int = 2048) throws -> PairMatchOutput {
        func invalid(_ field: String,_ message: String) -> MasterMatchError {
            .invalidOption(field:field,message:message)
        }
        guard unitsPerEm.isFinite,(16...16384).contains(unitsPerEm),axis.locations.count==2,axis.locations.allSatisfy(\.isFinite),axis.locations[0] != axis.locations[1],!axis.tag.isEmpty,
              reference.id != target.id,!reference.id.isEmpty,!target.id.isEmpty,reference.id.utf8.count<=255,target.id.utf8.count<=255,axis.tag.utf8.count<=64,
              options.fitTolerance.isFinite,options.fitTolerance>0,options.fitTolerance<=unitsPerEm/10 else { throw invalid("job","bounded UPM, distinct masters/locations and positive tolerance required") }
        guard !options.preserveStructure else { throw invalid("options.preserveStructure","match-pair prepares correspondence; use match review for structure-only review") }
        if options.referencePolicy == .fixed && options.maxAdditionalOnCurveNodes>0 {
            throw invalid("options.maxAdditionalOnCurveNodes","Fixed reference cannot add knots. Choose shared-subdivision with explicit absolute limits to permit shape-preserving splits.")
        }
        guard (256...4096).contains(renderHeight) else { throw invalid("renderHeight","expected 256...4096 pixels") }
        if reference.vector==nil && target.vector != nil { throw invalid("inputs","put the vector reference first for mixed inputs") }
        if reference.vector==nil && options.referencePolicy == .fixed { throw invalid("options.referencePolicy","two images require shared-subdivision; no existing vector reference is fixed") }
        if strategy == .retraceTarget && (reference.vector==nil || target.vector==nil) { throw invalid("strategy","retrace-target requires two outlines") }
        if strategy == .retraceBoth && (reference.vector==nil || options.referencePolicy == .fixed) { throw invalid("strategy","retrace-both requires an outline reference and shared-subdivision permission") }
        guard options.contourPairs.isEmpty || options.contourPairs.count==(reference.vector?.outline.contours.count ?? options.contourPairs.count),options.startNodes.isEmpty || options.startNodes.count==(reference.vector?.outline.contours.count ?? options.startNodes.count) else { throw invalid("options","correspondence overrides must match the reference contour count") }
        try MatchNodeBudget.validate(options)
        try RasterMasterMatcher.validateRasterOptions(rasterOptions,mode:"match-pair")
        for source in [reference,target] {
            if case .image(let image)=source { _ = try RasterMasterMatcher.preflightBoundary(image,options:rasterOptions,tolerance:options.fitTolerance) }
            if let v=source.vector { for (ci,c) in v.outline.contours.enumerated() { try MatchGeometry.validate(MatchRing(c),unitsPerEm:unitsPerEm,context:.init(stage:"input",masterID:v.id,contour:ci,existedBeforeFitting:true)) } }
        }
        var routes: [String]
        if strategy == .smart {
            if reference.vector==nil { routes=["joint-images","sequential-images"] }
            else {
                routes=["direct"]
                if target.vector != nil { routes.append("retrace-target") }
                if options.referencePolicy == .sharedSubdivision { routes.append("retrace-both") }
            }
        } else { routes=[strategy == .direct && reference.vector==nil ? "joint-images" : strategy.rawValue] }
        var reports: [PairCandidateReport]=[],results: [String:MasterMatchResult]=[:],renders: [String:Data]=[:]
        for route in routes {
            var receipt=PairCandidateReport(route:route,accepted:false)
            do {
                func image(_ input: PairInput) throws -> MatchRasterInput {
                    switch input {
                    case .image(let i):return i
                    case .outline(let v):
                        let r=try PairOutlineRenderer.render(v,unitsPerEm:unitsPerEm,pixelHeight:renderHeight)
                        let hash=SHA256.hash(data:r.image.imageData).map { String(format:"%02x",$0) }.joined()
                        receipt.renderedSources.append(.init(masterID:v.id,sha256:hash,transform:r.image.transform,pixelWidth:r.pixelWidth,pixelHeight:r.pixelHeight,unitsPerPixel:r.unitsPerPixel,paddingPixels:r.paddingPixels))
                        renders[route+"-"+(v.id==reference.id ? "reference" : "target")+".png"]=r.image.imageData
                        return r.image
                    }
                }
                var result: MasterMatchResult
                if route == "direct",let a=reference.vector,let b=target.vector {
                    result=try OutlineMatcher.match(.init(unitsPerEm:unitsPerEm,axis:axis,reference:a,target:b,options:options))
                } else if route == "direct" || route == "retrace-target" {
                    var routeOptions=options
                    if route == "retrace-target" { routeOptions.referencePolicy = .fixed }
                    result=try RasterMasterMatcher.match(.init(mode:.traceToReference,unitsPerEm:unitsPerEm,axis:axis,reference:reference.vector,images:[image(target)],options:routeOptions,rasterOptions:rasterOptions))
                } else if route == "sequential-images" {
                    let a=try image(reference),b=try image(target)
                    // Use the same neutral matcher for the internal single-image
                    // seed. Both copies share bytes and placement; no ordinary
                    // grid-zero tracing/math path or second affine is introduced.
                    let seedID=a.id=="reference-seed" ? "target-seed" : "reference-seed"
                    let copy=MatchRasterInput(id:seedID,imageData:a.imageData,transform:a.transform)
                    let seed=try RasterMasterMatcher.match(.init(mode:.traceBoth,unitsPerEm:unitsPerEm,
                        axis:axis,images:[a,copy],options:options,rasterOptions:rasterOptions))
                    let outline=seed.reference.outline
                    var fixed=options;fixed.referencePolicy = .fixed
                    result=try RasterMasterMatcher.match(.init(mode:.traceToReference,unitsPerEm:unitsPerEm,axis:axis,reference:.init(id:a.id,outline:outline),images:[b],options:fixed,rasterOptions:rasterOptions))
                } else {
                    result=try RasterMasterMatcher.match(.init(mode:.traceBoth,unitsPerEm:unitsPerEm,axis:axis,images:[image(reference),image(target)],options:options,rasterOptions:rasterOptions))
                }
                // Rasterization can move an extremum a fraction of a pixel.
                // Fit the existing nodes back INSIDE the original vector ink
                // envelope. Do not alter images or their placement. Acceptance
                // is still independently measured against the original vector.
                for (index,source) in [reference,target].enumerated() {
                    guard route != "direct",let original=source.vector,index==1 || options.referencePolicy == .sharedSubdivision else { continue }
                    let fitted=index==0 ? result.reference.outline : result.target.outline
                    let oldRings=try original.outline.contours.map(MatchRing.init),newRings=try fitted.contours.map(MatchRing.init)
                    let old=oldRings.dropFirst().reduce(oldRings[0].bounds) { $0.union($1.bounds) },new=newRings.dropFirst().reduce(newRings[0].bounds) { $0.union($1.bounds) }
                    if old.minY>new.minY || old.maxY<new.maxY {
                        let adjusted=try PairEnvelopeFitter.fit(fitted,source:original.outline,bounds:old,tolerance:options.fitTolerance)
                        let adjustedRings=try adjusted.contours.map(MatchRing.init)
                        let adjustedBounds=adjustedRings.dropFirst().reduce(adjustedRings[0].bounds) { $0.union($1.bounds) }
                        receipt.envelopeAdjustments.append(.init(masterID:source.id,previousYBounds:[new.minY,new.maxY],fittedYBounds:[adjustedBounds.minY,adjustedBounds.maxY],scaleY:1,translateY:0,method:"local-span-constraint"))
                        if index==0 { result.reference.outline=adjusted } else { result.target.outline=adjusted }
                    }
                }
                if !receipt.envelopeAdjustments.isEmpty {
                    var maximum=0.0
                    for source in result.rasterSources ?? [] {
                        let originalInput: PairInput=source.masterID==reference.id ? reference : target
                        let raster: MatchRasterInput
                        if case .image(let i)=originalInput { raster=i }
                        else {
                            let name=route+"-"+(source.masterID==reference.id ? "reference" : "target")+".png"
                            raster = .init(id:source.masterID,imageData:renders[name]!,transform:source.transform)
                        }
                        let outline=source.masterID==reference.id ? result.reference.outline : result.target.outline
                        let m=try RasterMasterMatcher.pairSourceDeviation(raster,outline:outline,options:rasterOptions,tolerance:options.fitTolerance)
                        guard m.upperBound<=options.fitTolerance else { throw MasterMatchError.fitDiagnostic(.init(code:"envelope-fit-deviation",message:"vertical envelope fitting bound \(m.upperBound)u exceeds rendered boundary tolerance \(options.fitTolerance)u",stage:"pair-envelope-verification",masterID:source.masterID,measuredDeviation:m.upperBound,allowedDeviation:options.fitTolerance,cause:"The candidate optimizer did not establish a fit satisfying both source extent and boundary fidelity")) }
                        maximum=max(maximum,m.upperBound)
                        if let i=result.rasterSources?.firstIndex(where: { $0.masterID==source.masterID }) { result.rasterSources![i].maximumBoundaryDeviation=m.upperBound }
                    }
                    for i in result.contours.indices { result.contours[i].maximumTargetDeviation=max(result.contours[i].maximumTargetDeviation,maximum) }
                    result.warnings.append("Retraced vertical envelope fitted inside original vector bounds; pair comparison records the adjustment and independent original-source limits.")
                }
                var deviations: [PairDeviation]=[]
                for (source,fitted) in [(reference,result.reference),(target,result.target)] {
                    let d: PairDeviation
                    switch source {
                    case .outline(let v):d=try PairGeometry.measure(v.outline,fitted.outline,tolerance:options.fitTolerance)
                    case .image(let i):d=try RasterMasterMatcher.pairSourceDeviation(i,outline:fitted.outline,options:rasterOptions,tolerance:options.fitTolerance)
                    }
                    deviations.append(d);receipt.sourceDeviations=deviations
                    guard d.upperBound<=options.fitTolerance else { throw MasterMatchError.fitDiagnostic(.init(code:"source-deviation",message:"\(source.id) independent source bound \(d.upperBound)u exceeds \(options.fitTolerance)u",stage:"pair-source-verification",masterID:source.id,measuredDeviation:d.upperBound,allowedDeviation:options.fitTolerance,cause:"Original source fidelity, including rendering and fitting")) }
                    if let v=source.vector {
                        let rb=try v.outline.contours.map(MatchRing.init).map(\.bounds),fb=try fitted.outline.contours.map(MatchRing.init).map(\.bounds)
                        let old=rb.dropFirst().reduce(rb[0]) { $0.union($1) },new=fb.dropFirst().reduce(fb[0]) { $0.union($1) }
                        guard new.maxY<=old.maxY+unitsPerEm*1e-12,new.minY>=old.minY-unitsPerEm*1e-12 else { throw MasterMatchError.geometry("\(source.id) retraced outline grows beyond the original vertical ink envelope") }
                    }
                }
                result.interpolation=try InterpolationValidator.validate(reference:result.reference.outline,target:result.target.outline,unitsPerEm:unitsPerEm,intervals:200)
                guard !result.interpolation.issues.contains(where: { $0.message != "smooth join tangency residual" }) else { throw MasterMatchError.geometry("201-position interpolation verification failed") }
                let on=result.reference.outline.contours.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count },total=result.reference.outline.contours.reduce(0) { $0+$1.nodes.count }
                guard on<=options.maxOnCurveNodes,total<=options.maxNodes else { throw MasterMatchError.nodeBudget("pair result exceeds absolute ceilings") }
                if options.referencePolicy == .fixed,let v=reference.vector, v.outline != result.reference.outline { throw MasterMatchError.geometry("fixed reference changed") }
                receipt.sourceDeviations=deviations;receipt.onCurveNodes=on;receipt.totalNodes=total
                receipt.referenceUnchanged=reference.vector.map { $0.outline==result.reference.outline } ?? false;receipt.targetUnchanged=target.vector.map { $0.outline==result.target.outline } ?? false
                let sourceResidual=try [reference.vector,target.vector].compactMap { $0 }.map { try InterpolationValidator.validate(reference:$0.outline,target:$0.outline,unitsPerEm:unitsPerEm,intervals:2).maximumTangencyResidual }.max() ?? 0
                receipt.excessSmoothJoinResidual=max(0,result.interpolation.maximumTangencyResidual-sourceResidual)
                receipt.accepted=true;results[route]=result
            } catch {
                receipt.refusal=String(describing:error);receipt.diagnostic=(error as? MasterMatchError)?.diagnostic
                if receipt.diagnostic==nil {
                    let code: String
                    switch error {
                    case MasterMatchError.topology: code="topology-mismatch"
                    case MasterMatchError.ambiguousContour,MasterMatchError.ambiguousStart: code="ambiguous-correspondence"
                    case MasterMatchError.nodeBudget: code="node-budget"
                    case MasterMatchError.fit: code="fit-refusal"
                    default: code="geometry-refusal"
                    }
                    receipt.diagnostic = .init(code:code,message:String(describing:error),stage:"pair-candidate",mode:route)
                }
            }
            reports.append(receipt)
        }
        let ranking=rank(reports.filter(\.accepted),routes:routes)
        let ranked=ranking.reports
        func hash(_ input: PairInput) throws -> String {
            switch input { case .outline(let v):return try OutlineMatcher.hash(v.outline)
            case .image(let i):return SHA256.hash(data:i.imageData).map { String(format:"%02x",$0) }.joined() }
        }
        let reasons=ranked.isEmpty ? ["No route met the unchanged limits; no matched geometry is recommended."] : ["Accepted geometry and 201 sampled interpolation positions precede ranking.","Source fidelity first; overlapping measurement intervals are ties.","\(ranking.tiedCount) candidate(s) in the fidelity tie; rank by total nodes, on-curves, then excess smooth-join residual.","Recommendation is measured geometry, not artistic quality or native HOI acceptance."]
        return .init(report:.init(strategy:strategy,options:options,sourceHashes:try [hash(reference),hash(target)],sourceOutlines:[reference.vector,target.vector].compactMap { $0 },candidates:reports,recommendedRoute:ranked.first?.route,reasons:reasons),results:results,renders:renders)
    }
}
