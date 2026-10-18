// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independently derived projection onto shared handle-ratio constraints.
import Foundation

public struct JointSmoothingRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var unitsPerEm: Double
    public var fitTolerance: Double
    public var reference: Outline
    public var target: Outline
    /// Immutable original artwork, including when target was previously fitted.
    public var sourceTarget: Outline
    public init(reference: Outline,target: Outline,sourceTarget: Outline,unitsPerEm: Double = 1000,fitTolerance: Double? = nil) {
        self.reference=reference;self.target=target;self.sourceTarget=sourceTarget
        self.unitsPerEm=unitsPerEm;self.fitTolerance=fitTolerance ?? unitsPerEm/1000
    }
    enum CodingKeys: String,CodingKey { case schemaVersion,unitsPerEm,fitTolerance,reference,target,sourceTarget }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(reference:try c.decode(Outline.self,forKey:.reference),target:try c.decode(Outline.self,forKey:.target),
            sourceTarget:try c.decode(Outline.self,forKey:.sourceTarget),unitsPerEm:try c.decodeIfPresent(Double.self,forKey:.unitsPerEm) ?? 1000,
            fitTolerance:try c.decodeIfPresent(Double.self,forKey:.fitTolerance))
        schemaVersion=try c.decode(Int.self,forKey:.schemaVersion)
    }
}

public struct JointSmoothingLocation: Codable, Sendable { public var contour: Int; public var node: Int }
public enum JointSmoothingStatus: String, Codable, Sendable { case smoothed,unchanged,refused }
public struct JointSmoothingReport: Codable, Sendable {
    public var status: JointSmoothingStatus
    public var reason: String?
    public var eligibleJoins: Int
    /// Changes in the returned target; empty on refusal.
    public var changedHandles: [JointSmoothingLocation]
    public var proposedHandleChanges: Int
    /// Measurement of a proposed repair; on refusal it does NOT describe output.
    public var proposalDeviation: PairDeviation?
    public var beforeMaximumTangencyResidual: Double?
    public var afterMaximumTangencyResidual: Double?
    public var referenceUnchanged: Bool = true
    public var structurePreserved: Bool = true
    public var sampleCount: Int = 201
    public var nativeHOIVerified: Bool = false
}
public struct JointSmoothingResult: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var kind: String = "beztrace-joint-smoothing"
    public var pathDataVersion: Int = 2
    public var engineVersion: String = BezierTraceVersion.engine
    public var unitsPerEm: Double
    public var fitTolerance: Double
    public var reference: Outline
    public var target: Outline
    public var sourceTargetHash: String
    public var report: JointSmoothingReport
}

/// Atomic, reference-locked smoothing of two already-corresponding masters.
/// Closed-form least movement in target control coordinates; a failed proposal
/// is not proof that every possible repair exceeds the source budget.
public enum JointMasterSmoother {
    public static func smooth(_ request: JointSmoothingRequest) throws -> JointSmoothingResult {
        try smooth(request,sourceMeasurement:nil)
    }

    /// Matchers retain original raster boundaries outside the neutral outline
    /// contract. Their callback certifies the COMPLETE proposal directly against
    /// that evidence, replacing (never adding to) the outline source allowance.
    static func smooth(_ request: JointSmoothingRequest,
                       sourceMeasurement: ((Outline) throws -> PairDeviation)?) throws -> JointSmoothingResult {
        let reference=request.reference,target=request.target,source=request.sourceTarget
        let upm=request.unitsPerEm,tolerance=request.fitTolerance
        guard request.schemaVersion==1,upm.isFinite,(16...16384).contains(upm),
              tolerance.isFinite,tolerance>0,tolerance<=upm/10 else {
            throw MasterMatchError.invalid("joint smoothing requires schema 1, bounded UPM and positive font-unit tolerance")
        }
        for outline in [reference,target,source] {
            guard !outline.contours.isEmpty,outline.contours.count<=64,outline.contours.reduce(0,{$0+$1.nodes.count})<=4096 else {
                throw MasterMatchError.invalid("joint smoothing outline resource limits")
            }
            for c in outline.contours { try MatchGeometry.validate(MatchRing(c),unitsPerEm:upm) }
        }
        // Check correspondence only after rejecting excessive input sizes.
        _=try InterpolationValidator.interpolate(reference:reference,target:target,factor:0)
        let coordinateScale=(reference.contours+target.contours).flatMap(\.nodes).reduce(upm) { max($0,abs($1.x),abs($1.y)) }
        let epsilon=max(upm*1e-10,coordinateScale*Double.ulpOfOne*128)
        let minimum=max(upm*1e-12,coordinateScale*Double.ulpOfOne*4)
        var report=JointSmoothingReport(status:.unchanged,reason:nil,eligibleJoins:0,changedHandles:[],proposedHandleChanges:0)
        let sourceHash=try OutlineMatcher.hash(source)
        func finish(_ accepted: Outline?,_ reason: String? = nil) -> JointSmoothingResult {
            var r=report
            if let reason { r.status = .refused;r.reason=reason;r.changedHandles=[];r.afterMaximumTangencyResidual=nil }
            return .init(unitsPerEm:upm,fitTolerance:tolerance,reference:reference,target:accepted ?? target,sourceTargetHash:sourceHash,report:r)
        }
        // Before is diagnostic only. Run the expensive geometry/nesting sweep
        // once on the complete proposal, which is the only editable output.
        report.beforeMaximumTangencyResidual=InterpolationValidator.maximumTangencyResidual(
            reference:reference,target:target,intervals:200)
        var proposal=target
        for ci in reference.contours.indices {
            let a=reference.contours[ci].nodes,b=target.contours[ci].nodes,n=a.count
            for j in a.indices where a[j].type != .offcurve && a[j].smooth && b[j].smooth {
                report.eligibleJoins+=1
                let previous=(j+n-1)%n,next=(j+1)%n
                let ri=a[j].point-a[previous].point,ro=a[next].point-a[j].point
                let ti=b[j].point-b[previous].point,to=b[next].point-b[j].point
                let incoming=ri.matchMagnitude,outgoing=ro.matchMagnitude
                guard incoming>minimum,outgoing>minimum,ri.dot(ro)>0,
                      abs(ri.cross(ro))/max((ri+ro).matchMagnitude,minimum)<=epsilon else {
                    return finish(nil,"Reference smooth join \(ci):\(j) is degenerate or non-collinear; reference remains fixed")
                }
                let alpha=incoming/(incoming+outgoing),beta=outgoing/(incoming+outgoing)
                let moveIn=a[previous].type == .offcurve,moveOut=a[next].type == .offcurve
                let w:Vector2D
                if moveIn && moveOut { w=(ti*alpha+to*beta)/(alpha*alpha+beta*beta) }
                else if moveIn { w=to/beta }
                else if moveOut { w=ti/alpha }
                else { w=ti+to }
                // For every interpolation factor, the two tangent vectors are
                // alpha*W(t), beta*W(t). Bound their minimum length analytically
                // so a zero between the 201 samples cannot pass unnoticed.
                let r=ri+ro,d=w-r,denominator=d.dot(d)
                let factor=denominator>0 ? min(1,max(0,-r.dot(d)/denominator)) : 0
                guard w.isFinite,min(alpha,beta)*(r+d*factor).matchMagnitude>minimum+epsilon*4 else {
                    return finish(nil,"Smooth join \(ci):\(j) would collapse between masters")
                }
                if !moveIn && !moveOut && max((ti-w*alpha).matchMagnitude,(to-w*beta).matchMagnitude)>epsilon {
                    return finish(nil,"Smooth line join \(ci):\(j) requires moving protected on-curves")
                }
                // Already compatible ratios are kept bit-for-bit (idempotence).
                if max((ti-w*alpha).matchMagnitude,(to-w*beta).matchMagnitude)<=epsilon { continue }
                for (index,point,movable) in [(previous,b[j].point+w*(-alpha),moveIn),(next,b[j].point+w*beta,moveOut)] where movable {
                    guard SourceGeometryVerifier.valid(point) else { return finish(nil,"Smoothing handle exceeds finite coordinate limits") }
                    proposal.contours[ci].nodes[index].x=point.x;proposal.contours[ci].nodes[index].y=point.y
                }
            }
        }
        var changes:[JointSmoothingLocation]=[]
        for ci in target.contours.indices {
            for ni in target.contours[ci].nodes.indices where target.contours[ci].nodes[ni] != proposal.contours[ci].nodes[ni] {
                changes.append(.init(contour:ci,node:ni))
            }
        }
        report.proposedHandleChanges=changes.count
        do {
            // Measure ONCE against original source after ALL join projections.
            // No join receives its own separately spendable source allowance.
            let deviation=try sourceMeasurement?(proposal) ?? PairGeometry.measure(source,proposal,tolerance:tolerance)
            report.proposalDeviation=deviation
            guard deviation.upperBound<=tolerance else { return finish(nil,"Proposed source bound \(deviation.upperBound)u exceeds \(tolerance)u; a fitting refusal, not an impossibility proof") }
            for ci in target.contours.indices {
                let old=try MatchRing(target.contours[ci]),new=try MatchRing(proposal.contours[ci])
                try MatchGeometry.validate(new,unitsPerEm:upm)
                for (a,b) in zip(old.spans,new.spans) where a.curve != b.curve {
                    let evidence=try SourceGeometryVerifier.prepare([a.curve],tolerance:tolerance)
                    let check=try SourceGeometryVerifier.verify(b.curve,source:evidence,tolerance:tolerance,
                        start:a.curve.start,end:a.curve.end,startTangent:nil,endTangent:nil)
                    guard check.accepted else { return finish(nil,"Smoothing introduces an unverified local shape, inflection or ordered correspondence") }
                }
            }
            let oldRings=try target.contours.map(MatchRing.init),newRings=try proposal.contours.map(MatchRing.init)
            guard MatchGeometry.depths(oldRings)==MatchGeometry.depths(newRings) else { return finish(nil,"Smoothing changes nesting") }
            let after=try InterpolationValidator.validate(reference:reference,target:proposal,unitsPerEm:upm,intervals:200)
            guard after.issues.isEmpty,after.maximumTangencyResidual<=epsilon*8 else { return finish(nil,"Joint smoothing did not establish regular smooth interpolation") }
            report.afterMaximumTangencyResidual=after.maximumTangencyResidual
            report.changedHandles=changes;report.status=changes.isEmpty ? .unchanged : .smoothed
            return finish(proposal)
        } catch {
            return finish(nil,"Independent smoothing verification refused: \(error)")
        }
    }
}
