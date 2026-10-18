// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Optional master-set extension; the published single-image pipeline is unchanged.

import CryptoKit
import Foundation

public enum RasterMatchMode: String, Codable, Sendable {
    case traceToReference = "trace-to-reference"
    case traceBoth = "trace-both"
}

public struct MatchRasterInput: Codable, Sendable {
    public var id: String
    public var imageData: Data
    /// [a,b,c,d,tx,ty], from neutral y-up 1088-height image coordinates to font units.
    public var transform: [Double]
    public init(id: String, imageData: Data, transform: [Double]) {
        self.id = id; self.imageData = imageData; self.transform = transform
    }
}

public struct RasterMatchOptions: Codable, Sendable {
    public var threshold: UInt8? = nil
    public var invert: Bool = false
    public var minimumContourArea: Double = 100
    public var smoothing: Double = 1
    public var cornerThresholdDegrees: Double = 12
    public init() {}
}

public struct RasterMasterMatchRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var mode: RasterMatchMode
    public var unitsPerEm: Double
    public var axis: MatchAxis
    public var reference: MatchMaster?
    public var images: [MatchRasterInput]
    public var options: MasterMatchOptions
    public var rasterOptions: RasterMatchOptions
    public init(mode: RasterMatchMode, unitsPerEm: Double = 1000, axis: MatchAxis,
                reference: MatchMaster? = nil, images: [MatchRasterInput],
                options: MasterMatchOptions? = nil, rasterOptions: RasterMatchOptions = .init()) {
        self.mode = mode; self.unitsPerEm = unitsPerEm; self.axis = axis; self.reference = reference
        self.images = images; self.options = options ?? .init(fitTolerance: unitsPerEm / 1000)
        self.rasterOptions = rasterOptions
    }
}

public struct RasterMatchSourceReport: Codable, Sendable {
    public var masterID: String
    public var sha256: String
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var transform: [Double]
    public var threshold: UInt8
    public var invert: Bool
    public var maximumBoundaryDeviation: Double
    public var options: RasterMatchOptions
    public var contourOrder: [Int]
    public var startBoundaryPoints: [Int]
    public var reversedContours: [Bool]
}

public struct RasterMatchPlanningResult: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var kind: String = "beztrace-raster-plan"
    public var pathDataVersion: Int = 2
    public var engineVersion: String = BezierTraceVersion.engine
    public var unitsPerEm: Double
    public var outlines: [Outline]
    public var sourceNodeIndices: [[[Int?]]]
}

public enum RasterMasterMatcher {
    // Internal observation seam for detached regression evidence. No I/O or
    // environment-dependent behavior enters the production matching path.
    struct FitEvidence: Codable {
        struct Section: Codable {
            var referenceCurve: [Double]
            var targetCurve: [Double]
            var referenceLine: Bool
            var targetLine: Bool
            var error: Double
            var accepted: Bool
            var reason: String
        }
        var contour: Int
        var targetContour: Int
        var reference: Contour
        var boundary: Contour
        var boundarySourceNodes: [Int?]
        var boundaryRoles: [Int?]
        var originalBoundary: [[Double]]
        var cuts: [Double]
        var targetCuts: [Double]
        var mappedCuts: [Double]
        var sections: [Section]
    }
    private struct Boundary {
        var ring: MatchRing
        var original: [Point2D]
        var reversedOriginal: Bool = false
    }
    private struct Extracted {
        var boundaries: [Boundary]
        var report: RasterMatchSourceReport
    }

    public static func match(_ request: RasterMasterMatchRequest) throws -> MasterMatchResult {
        try match(request, observing: nil)
    }

    static func match(_ request: RasterMasterMatchRequest, observing: ((FitEvidence) -> Void)?) throws -> MasterMatchResult {
        try validateRequest(request)
        try MatchNodeBudget.validate(request.options)
        let o = request.rasterOptions
        var extracted = try request.images.map { try extract($0, options: o, tolerance: request.options.fitTolerance) }
        let reference: [MatchRing]
        let targets: [Boundary]
        let referenceID: String
        let targetID: String
        if request.mode == .traceToReference {
            guard let source = request.reference else { throw MasterMatchError.invalid("a vector reference is required") }
            reference = try source.outline.contours.map(MatchRing.init)
            referenceID = source.id; targetID = request.images[0].id; targets = extracted[0].boundaries
            for (ci, ring) in reference.enumerated() {
                try MatchGeometry.validate(ring, unitsPerEm: request.unitsPerEm,
                    context:.init(stage:"input",role:"reference",masterID:referenceID,contour:ci,existedBeforeFitting:true))
            }
        } else {
            reference = extracted[0].boundaries.map(\.ring); targets = extracted[1].boundaries
            referenceID = request.images[0].id; targetID = request.images[1].id
        }
        guard !referenceID.isEmpty, referenceID.utf8.count<=255, referenceID != targetID, !reference.isEmpty, reference.count == targets.count,
              reference.count <= 64 else { throw MasterMatchError.topology("reference and image contour counts differ") }
        guard request.options.startNodes.isEmpty || request.options.startNodes.count == reference.count else {
            throw MasterMatchError.invalid("startNodes count")
        }
        let pairs = try OutlineMatcher.pair(reference, targets.map(\.ring), overrides: request.options.contourPairs)
        let rb = reference.dropFirst().reduce(reference[0].bounds) { $0.union($1.bounds) }
        let tb = targets.dropFirst().reduce(targets[0].ring.bounds) { $0.union($1.ring.bounds) }
        var aa: [Contour] = [], bb: [Contour] = [], reports: [MatchContourReport] = []
        var deviations = Array(repeating: 0.0, count: extracted.count)
        for ci in reference.indices {
            let r = reference[ci], originalTarget = targets[pairs[ci]]
            let reverse = r.area * originalTarget.ring.area < 0
            var t = reverse ? originalTarget.ring.reversed() : originalTarget.ring
            let offset = try OutlineMatcher.startingPoint(r, t, referenceBounds: rb, targetBounds: tb,
                override: request.options.startNodes.isEmpty ? -1 : request.options.startNodes[ci], contour: ci)
            t = t.rotated(offset)
            let map = OutlineMatcher.anchors(r, t)
            let rf = r.fractions(), tf = t.fractions()
            let mandatory = request.mode == .traceToReference ? rf+[1] : [0,1]
            var cuts = request.mode == .traceToReference ? mandatory :
                unique([0,0.25,0.5,0.75,1] + r.spans.indices.filter { abs(OutlineMatcher.signature(r,$0))==1 }.map { rf[$0] })
            var targetCuts=cuts.map { OutlineMatcher.warp($0,map) }
            let referenceCount=request.mode == .traceToReference ? reference.reduce(0) { $0+$1.spans.count } : nil
            let limit=MatchNodeBudget.limit(request.options,referenceCount:referenceCount)
            let remainingReference=reference.dropFirst(ci+1).reduce(0) { $0 + (request.mode == .traceToReference ? $1.spans.count : 3) }
            let used=aa.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count }
            let contourLimit=limit-used-remainingReference
            _ = try MatchNodeBudget.check(used+cuts.count-1+remainingReference,referenceCount:referenceCount,options:request.options,
                detail:"contour \(ci) initial structure")
            // Optimize target correspondence and handles before spending points.
            // Original reference knots remain fixed; only target sampling moves.
            MatchingStructureFitter.optimizeTargetCuts(reference:r,target:t,cuts:cuts,targetCuts:&targetCuts,mode:request.mode,
                policy:request.options.referencePolicy,tolerance:request.options.fitTolerance,map:map)
            var fittedA: MatchRing?, fittedB: MatchRing?
            var refinedFixed=false
            for _ in 0..<1025 {
                prune(reference:r,target:t,cuts:&cuts,targetCuts:&targetCuts,mandatory:mandatory,
                    mode:request.mode,policy:request.options.referencePolicy,tolerance:request.options.fitTolerance)
                var sections=zip(cuts,cuts.dropFirst()).enumerated().map { i,pair in
                    MatchingStructureFitter.section(reference:r,target:t,start:pair.0,end:pair.1,targetStart:targetCuts[i],targetEnd:targetCuts[i+1],
                        mode:request.mode,policy:request.options.referencePolicy,tolerance:request.options.fitTolerance)
                }
                if request.options.referencePolicy == .fixed && sections.contains(where:{ !$0.accepted }) {
                    refinedFixed=true
                    // The supplied reference is also a legitimate target-fit
                    // candidate. Certify it against the original placed boundary
                    // before replacing it with an inferior numerical solution.
                    let seedError=boundaryDeviation(originalTarget.original,r,tolerance:request.options.fitTolerance)
                    if seedError<=request.options.fitTolerance*(15.0/16) {
                        sections=r.spans.map { .init(a:$0,b:$0,error:seedError,accepted:true,
                            score:seedError,reason:"reference seed certified against the original complete boundary") }
                    }
                }
                if request.options.referencePolicy == .fixed && sections.contains(where:{ !$0.accepted }) {
                    MatchingStructureFitter.optimizeTargetCuts(reference:r,target:t,cuts:cuts,targetCuts:&targetCuts,mode:request.mode,
                        policy:request.options.referencePolicy,tolerance:request.options.fitTolerance,map:map,refine:true)
                    sections=MatchingStructureFitter.refineFixedSections(reference:r,target:t,cuts:cuts,targetCuts:targetCuts,
                        mode:request.mode,tolerance:request.options.fitTolerance)
                }
                let failed=sections.indices.filter { !sections[$0].accepted }
                if let observing {
                    func coordinates(_ c: CubicBezier) -> [Double] {
                        [c.start.x,c.start.y,c.control1.x,c.control1.y,c.control2.x,c.control2.y,c.end.x,c.end.y]
                    }
                    let boundary=t.serialized()
                    observing(.init(contour:ci,targetContour:pairs[ci],reference:r.serialized().0,
                        boundary:boundary.0,boundarySourceNodes:boundary.1,boundaryRoles:t.spans.map(\.featureRole),
                        originalBoundary:originalTarget.original.map { [$0.x,$0.y] },cuts:cuts,targetCuts:targetCuts,
                        mappedCuts:cuts.map { OutlineMatcher.warp($0,map) },
                        sections:sections.map { .init(referenceCurve:coordinates($0.a.curve),targetCurve:coordinates($0.b.curve),
                            referenceLine:$0.a.line,targetLine:$0.b.line,error:$0.error,accepted:$0.accepted,reason:$0.reason) }))
                }
                if failed.isEmpty {
                    // Jointly remove dispensable fitter splits. Reference knots
                    // and intentional target corners remain mandatory.
                    prune(reference:r,target:t,cuts:&cuts,targetCuts:&targetCuts,mandatory:mandatory,
                        mode:request.mode,policy:request.options.referencePolicy,tolerance:request.options.fitTolerance)
                    let final=request.options.referencePolicy == .fixed ? sections : zip(cuts,cuts.dropFirst()).enumerated().map { i,p in
                        MatchingStructureFitter.section(reference:r,target:t,start:p.0,end:p.1,targetStart:targetCuts[i],targetEnd:targetCuts[i+1],
                            mode:request.mode,policy:request.options.referencePolicy,tolerance:request.options.fitTolerance)
                    }
                    fittedA = MatchRing(spans:final.map(\.a),prefix:r.prefix)
                    fittedB = MatchRing(spans:final.map(\.b),prefix:r.prefix); break
                }
                let worst=failed.max { sections[$0].score<sections[$1].score }!
                let reason=sections[worst].reason
                if request.options.referencePolicy == .fixed {
                    let start=t.location(targetCuts[worst]).0, end=t.location(targetCuts[worst+1]).0
                    let cause=reason.contains("corner") ? "unassigned-corner" :
                        reason.contains("safety") ? "unsafe-handles" : "fit-not-established"
                    throw MasterMatchError.fitDiagnostic(.init(code:"fixed-structure-fit",
                        message:"Contour \(ci), section \(worst): fixed-structure fitting did not establish an acceptable target: \(reason). Review the reported boundary span and source nodes; no tolerance or node budget was increased",
                        stage:"fitting",role:"target",masterID:targetID,mode:request.mode.rawValue,
                        locations:[.init(contour:ci,segment:worst,startNode:r.spans[worst].startSource,
                            endNode:r.spans[(worst+1)%r.spans.count].startSource,parameterRange:[0,1])],
                        existedBeforeFitting:false,section:worst,measuredDeviation:sections[worst].error,
                        allowedDeviation:request.options.fitTolerance*(15.0/16),cause:cause,
                        boundarySpan:.init(contour:pairs[ci],startPoint:t.spans[start].startSource ?? 0,
                            endPoint:t.spans[end].startSource ?? 0,fractions:[targetCuts[worst],targetCuts[worst+1]])))
                }
                guard cuts.count-1<contourLimit else {
                    throw MasterMatchError.nodeBudget("contour \(ci), section \(worst): \(reason); using \(used+cuts.count-1+remainingReference) of \(limit) on-curves across the glyph")
                }
                let start=cuts[worst], end=cuts[worst+1], ts=targetCuts[worst], te=targetCuts[worst+1]
                let corner=t.spans.indices.first { abs(OutlineMatcher.signature(t,$0))==1 && tf[$0]>ts+1e-7 && tf[$0]<te-1e-7 }
                let splitTarget=corner.map { tf[$0] } ?? errorSplit(sections[worst].b,boundary:t,start:ts,end:te)
                // A split must describe the same shape location in both
                // masters. Equal fractions within a warped span can place a
                // lower-bowl point halfway around a terminal in the other.
                let splitReference=OutlineMatcher.warp(splitTarget,map,inverse:true)
                let safeReference=min(end-(end-start)*0.05,max(start+(end-start)*0.05,splitReference))
                let safeTarget=min(te-(te-ts)*0.05,max(ts+(te-ts)*0.05,splitTarget))
                cuts.insert(safeReference,at:worst+1)
                targetCuts.insert(safeTarget,at:worst+1)
                MatchingStructureFitter.optimizeTargetCuts(reference:r,target:t,cuts:cuts,targetCuts:&targetCuts,mode:request.mode,
                    policy:request.options.referencePolicy,tolerance:request.options.fitTolerance,map:map)
            }
            guard var a = fittedA, var b = fittedB else { throw MasterMatchError.fit(ci,"raster fitting did not converge") }
            b=polishSmooth(b,other:a,boundary:originalTarget.original,tolerance:request.options.fitTolerance)
            if request.mode == .traceBoth {
                a=polishSmooth(a,other:b,boundary:extracted[0].boundaries[ci].original,tolerance:request.options.fitTolerance)
                a=rasterConnections(a)
            }
            b=rasterConnections(b)
            if refinedFixed {
                // Respect the placed image's actual envelope, including optical
                // overshoot. No cap-height metric or new affine is inferred.
                b=withinEnvelope(b,bounds:tb,boundary:t,cuts:targetCuts,tolerance:request.options.fitTolerance)
            }
            if refinedFixed && boundaryDeviation(originalTarget.original,b,tolerance:request.options.fitTolerance)>request.options.fitTolerance {
                // The reduced span objective can pass while the raw-boundary
                // certificate fails after join/envelope constraints. Optimize
                // against the raw source before refusing; all gates stay fixed.
                b=refineRawBoundary(b,points:originalTarget.original,bounds:tb,tolerance:request.options.fitTolerance)
                b=rasterConnections(b)
            }
            try MatchGeometry.validate(a,unitsPerEm: request.unitsPerEm,context:.init(stage:"fitted",role:"reference",masterID:referenceID,contour:ci,existedBeforeFitting:request.mode == .traceToReference ? false : nil))
            try MatchGeometry.validate(b,unitsPerEm: request.unitsPerEm,context:.init(stage:"fitted",role:"target",masterID:targetID,contour:ci))
            let targetError = boundaryDeviation(originalTarget.original,b, tolerance: request.options.fitTolerance)
            guard targetError <= request.options.fitTolerance else {
                throw MasterMatchError.fitDiagnostic(.init(code:"boundary-deviation",
                    message:"Contour \(ci): fitted target deviation \(targetError) from the original extracted boundary exceeds \(request.options.fitTolerance)",
                    stage:"fitted",role:"target",masterID:targetID,mode:request.mode.rawValue,
                    existedBeforeFitting:false,approximationTolerance:request.options.fitTolerance/32,
                    measuredDeviation:targetError,allowedDeviation:request.options.fitTolerance,cause:"original-boundary-budget",
                    boundarySpan:.init(contour:pairs[ci],startPoint:0,endPoint:originalTarget.original.count-1,fractions:[0,1])))
            }
            deviations[extracted.count-1] = max(deviations.last!,targetError)
            if request.mode == .traceBoth {
                let error = boundaryDeviation(extracted[0].boundaries[ci].original,a,tolerance: request.options.fitTolerance)
                guard error <= request.options.fitTolerance else { throw MasterMatchError.fit(ci,"reference image deviation \(error) exceeds tolerance") }
                deviations[0] = max(deviations[0],error)
            }
            let ad = request.mode == .traceToReference && request.options.referencePolicy == .fixed
                ? (request.reference!.outline.contours[ci], request.reference!.outline.contours[ci].nodes.indices.map { Optional($0) })
                : a.serialized(prefix: r.prefix)
            let bd = b.serialized(prefix: r.prefix)
            aa.append(ad.0); bb.append(bd.0)
            reports.append(.init(referenceContour:ci,targetContour:pairs[ci],targetStartNode:t.spans[0].startSource ?? 0,
                targetReversed:reverse,insertedReferenceNodes:request.mode == .traceToReference ? max(0,a.spans.count-r.spans.count) : a.spans.count,
                insertedTargetNodes:b.spans.count,maximumTargetDeviation:targetError,
                referenceSourceNodes:request.mode == .traceToReference ? ad.1 : Array(repeating:nil,count:ad.0.nodes.count),
                targetSourceNodes:Array(repeating:nil,count:bd.0.nodes.count),nodeIDs:ad.0.nodes.indices.map { "c\(ci).n\($0)" }))
            reports[ci].targetContour = ci
            reports[ci].targetStartNode = bd.0.nodes.firstIndex { $0.type != .offcurve }!
            reports[ci].targetReversed = false
            let last = extracted.count-1
            extracted[last].report.contourOrder.append(pairs[ci])
            extracted[last].report.startBoundaryPoints.append(t.spans[0].startSource ?? 0)
            extracted[last].report.reversedContours.append(reverse != originalTarget.reversedOriginal)
            if request.mode == .traceBoth {
                extracted[0].report.contourOrder.append(ci)
                extracted[0].report.startBoundaryPoints.append(r.spans[0].startSource ?? 0)
                extracted[0].report.reversedContours.append(extracted[0].boundaries[ci].reversedOriginal)
            }
        }
        let a = MatchMaster(id:referenceID,outline:Outline(contours:aa)), b = MatchMaster(id:targetID,outline:Outline(contours:bb))
        let linear = request.options.smoothJoins ? MatchSmoothing.pending() :
            try InterpolationValidator.validate(reference:a.outline,target:b.outline,unitsPerEm:request.unitsPerEm)
        if let invalid = linear.issues.first(where: { $0.message != "smooth join tangency residual" }) {
            if let diagnostic = invalid.diagnostic { throw MasterMatchError.geometryDiagnostic(diagnostic) }
            throw MasterMatchError.geometry("raster interpolation fails at \(invalid.factor): \(invalid.message)")
        }
        let sources = [request.mode == .traceToReference ? request.reference! : a,b]
        for i in extracted.indices { extracted[i].report.maximumBoundaryDeviation = deviations[i] }
        var result = MasterMatchResult(unitsPerEm:request.unitsPerEm,axis:request.axis,reference:a,target:b,
            options:request.options,sourceHashes:try sources.map { try OutlineMatcher.hash($0.outline) },sourceMasters:sources,
            contours:reports,interpolation:linear,
            warnings:["Raster matching uses extracted silhouette boundaries and sampled linear verification; review native interpolation before Apply."],
            rasterSources:extracted.map(\.report))
        result.nodeBudget = try MatchNodeBudget.check(aa.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count },
            referenceCount:request.mode == .traceToReference ? reference.reduce(0) { $0+$1.spans.count } : nil, options:request.options,totalNodes:aa.reduce(0) { $0+$1.nodes.count })
        // These are the unsimplified, placed marching-squares boundaries, not
        // the fitted sourceMasters used for node mappings/file exchange.
        let originalBoundaries=pairs.map { targets[$0].original }
        result=try MatchSmoothing.apply(result) { proposal in
            let rings=try proposal.contours.map(MatchRing.init),eps=request.options.fitTolerance/200
            var lower=0.0,upper=0.0
            for (raw,ring) in zip(originalBoundaries,rings) {
                let closed=raw.last == raw.first ? raw : raw+[raw[0]]
                let deviation=try PairGeometry.measure(closed,PairGeometry.flatten(ring,epsilon:eps),
                    tolerance:request.options.fitTolerance,flattenAllowance:eps)
                lower=max(lower,deviation.lowerBound);upper=max(upper,deviation.upperBound)
            }
            return .init(lowerBound:lower,upperBound:upper,uncertainty:upper-lower)
        }
        if let smoothing=result.jointSmoothing,let i=result.rasterSources?.indices.last {
            result.rasterSources![i].maximumBoundaryDeviation=smoothing.proposalDeviation!.upperBound
        }
        return result
    }

    private static func validateRequest(_ request: RasterMasterMatchRequest) throws {
        let o = request.rasterOptions
        func require(_ valid: Bool, _ field: String, _ value: String, _ expectation: String, _ range: [Double]? = nil) throws {
            guard valid else {
                let boundedValue = String(value.prefix(256))
                throw MasterMatchError.invalidDiagnostic(.init(code:"invalid-option",
                    message:"\(field) provided \(boundedValue); expected \(expectation) (\(request.mode.rawValue))",
                    stage:"request-validation",mode:request.mode.rawValue,field:field,providedValue:boundedValue,allowedRange:range))
            }
        }
        try require(request.schemaVersion == 1,"schemaVersion",String(request.schemaVersion),"1")
        try require(request.unitsPerEm.isFinite && (16...16384).contains(request.unitsPerEm),"unitsPerEm",String(request.unitsPerEm),"finite value in [16, 16384]",[16,16384])
        try require(request.axis.locations.count == 2 && request.axis.locations.allSatisfy(\.isFinite)
            && request.axis.locations[0] != request.axis.locations[1],"axis.locations",String(describing:request.axis.locations),"two distinct finite values")
        try require(!request.axis.tag.isEmpty && request.axis.tag.utf8.count <= 64,"axis.tag",request.axis.tag,"1...64 UTF-8 bytes")
        try require(request.options.fitTolerance.isFinite && request.options.fitTolerance > 0 && request.options.fitTolerance <= request.unitsPerEm/10,
            "options.fitTolerance",String(request.options.fitTolerance),"finite value > 0 and <= UPM/10")
        try validateRasterOptions(o,mode:request.mode.rawValue)
        try require(request.images.count == (request.mode == .traceBoth ? 2 : 1),"images.count",String(request.images.count),request.mode == .traceBoth ? "2" : "1")
        for (i,image) in request.images.enumerated() {
            try require(!image.id.isEmpty && image.id.utf8.count <= 255,"images[\(i)].id",image.id,"1...255 UTF-8 bytes")
        }
        try require(!request.options.preserveStructure,"options.preserveStructure",String(request.options.preserveStructure),
            "false or omitted: preserveStructure reviews existing vector correspondence; raster tracing uses referencePolicy=fixed with explicit node budgets to retain reference structure")
        if request.mode == .traceBoth {
            try require(request.options.referencePolicy == .sharedSubdivision,"options.referencePolicy",request.options.referencePolicy.rawValue,"shared-subdivision for joint tracing")
            try require(request.reference == nil,"reference","present","absent for joint tracing")
        }
    }

    static func validateRasterOptions(_ o: RasterMatchOptions, mode: String) throws {
        for (field,value,range) in [("smoothing",o.smoothing,[0.25,3.0]),
            ("cornerThresholdDegrees",o.cornerThresholdDegrees,[1.0,60.0]),
            ("minimumContourArea",o.minimumContourArea,[0.0,1000.0])] {
            guard value.isFinite && (range[0]...range[1]).contains(value) else {
                throw MasterMatchError.invalidDiagnostic(.init(code:"invalid-option",
                    message:"rasterOptions.\(field) provided \(value); allowed range [\(range[0]), \(range[1])] (\(mode))",
                    stage:"request-validation",mode:mode,field:"rasterOptions.\(field)",providedValue:String(value),allowedRange:range))
            }
        }
    }

    /// Uses exactly the matching extraction path, without fitting or changing options.
    static func preflightBoundary(_ image: MatchRasterInput, options: RasterMatchOptions, tolerance: Double) throws -> ([MatchRing], RasterMatchSourceReport) {
        let extracted = try extract(image,options:options,tolerance:tolerance)
        return (extracted.boundaries.map(\.ring),extracted.report)
    }

    /// Detached selection geometry for resolving raster correspondence failures.
    /// No fitting or interpolation acceptance is claimed by a planning result.
    public static func plan(_ request: RasterMasterMatchRequest) throws -> RasterMatchPlanningResult {
        try validateRequest(request)
        let sources = try request.images.map { try extract($0,options:request.rasterOptions,tolerance:request.options.fitTolerance) }
        var outlines: [Outline] = [], indices: [[[Int?]]] = []
        if request.mode == .traceToReference {
            guard let reference = request.reference else { throw MasterMatchError.invalid("a vector reference is required") }
            _ = try reference.outline.contours.map(MatchRing.init)
            outlines.append(reference.outline)
            indices.append(reference.outline.contours.map { $0.nodes.indices.map { Optional($0) } })
        }
        for source in sources {
            let data = source.boundaries.map { $0.ring.serialized(prefix:0) }
            guard data.reduce(0,{ $0+$1.0.nodes.count }) <= 4096 else { throw MasterMatchError.invalid("raster selector point limit") }
            outlines.append(Outline(contours:data.map { $0.0 })); indices.append(data.map { $0.1 })
        }
        return RasterMatchPlanningResult(unitsPerEm:request.unitsPerEm,outlines:outlines,sourceNodeIndices:indices)
    }

    // Independent match-pair acceptance against unsimplified extracted coverage.
    static func pairSourceDeviation(_ input: MatchRasterInput, outline: Outline,
                                    options: RasterMatchOptions, tolerance: Double) throws -> PairDeviation {
        let source=try extract(input,options:options,tolerance:tolerance)
        let rings=try outline.contours.map(MatchRing.init)
        let pairs=try OutlineMatcher.pair(source.boundaries.map(\.ring),rings,overrides:[])
        let eps=tolerance/200
        var lo=0.0,hi=0.0
        for i in source.boundaries.indices {
            var raw=source.boundaries[i].original
            if raw.last != raw.first { raw.append(raw[0]) }
            let m=try PairGeometry.measure(raw,PairGeometry.flatten(rings[pairs[i]],epsilon:eps),tolerance:tolerance,flattenAllowance:eps)
            lo=max(lo,m.lowerBound);hi=max(hi,m.upperBound)
        }
        return .init(lowerBound:lo,upperBound:hi,uncertainty:hi-lo)
    }

    private static func extract(_ input: MatchRasterInput, options: RasterMatchOptions, tolerance: Double) throws -> Extracted {
        let m = input.transform
        guard m.count == 6, m.allSatisfy({ $0.isFinite && abs($0) <= 1e9 }),
              abs(m[0]*m[3]-m[1]*m[2]) > 1e-12,
              !input.imageData.isEmpty, input.imageData.count <= 16*1024*1024 else {
            throw MasterMatchError.invalid("bounded image data and a non-singular six-value canvas transform are required")
        }
        let extraction: ContourExtractionResult
        do {
            extraction = try ContourPipeline.extract(data:input.imageData,options:.init(
                threshold:options.threshold.map(ThresholdMethod.fixed) ?? .otsu,invert:options.invert,
                minimumContourArea:options.minimumContourArea,collapseBlockedScale:false,recoverLowResolution:false))
        } catch { throw MasterMatchError.invalid("raster extraction failed: \(error)") }
        guard extraction.contours.count <= 64, extraction.contours.reduce(0,{ $0+$1.points.count }) <= 131072 else {
            throw MasterMatchError.invalid("raster boundary resource limit")
        }
        let prepared = extraction.preparedRaster, scale = 1088 / Double(prepared.raster.height)
        func placed(_ p: Point2D) -> Point2D {
            Point2D(x:(m[0]*p.x+m[2]*p.y)*scale+m[4],y:(m[1]*p.x+m[3]*p.y)*scale+m[5])
        }
        var config = TraceConfiguration.capturedDefaults
        config.smoothing = options.smoothing; config.cornerThresholdDegrees = options.cornerThresholdDegrees
        var boundaries = try extraction.contours.map { contour -> Boundary in
            var roles: [Int:Int] = [:]
            if case .plan(let plan) = ContourPlanner.plan(contour:contour,configuration:config,raster:nil) {
                for split in plan.splits {
                    let position = plan.smoothed[split.index]
                    var index = contour.points.indices.min { contour.points[$0].matchDistance(to:position) < contour.points[$1].matchDistance(to:position) }!
                    if split.kind == .corner || split.kind == .tangent {
                        // The planner locates smoothed corners. Restore the
                        // corresponding concentrated turn on the raw boundary.
                        let turns = ContourPlanner.vertexTurns(contour.points)
                        let nearby = (-8...8).map { (index+$0+contour.points.count)%contour.points.count }
                        if let sharp = nearby.filter({ abs(turns[$0])>0.2 }).min(by: {
                            contour.points[$0].matchDistance(to:position)<contour.points[$1].matchDistance(to:position)
                        }) { index = sharp }
                        else if let peak = nearby.max(by: {
                            abs(turns[$0]) == abs(turns[$1])
                                ? contour.points[$0].matchDistance(to:position)>contour.points[$1].matchDistance(to:position)
                                : abs(turns[$0])<abs(turns[$1])
                        }) { index = peak }
                    }
                    let before = contour.points[(index+contour.points.count-1)%contour.points.count]
                    let after = contour.points[(index+1)%contour.points.count]
                    let d = after-before
                    let turns = ContourPlanner.vertexTurns(contour.points)
                    let net = (-8...8).reduce(0.0) { $0+turns[(index+$1+turns.count)%turns.count] }
                    let sign = net >= 0 ? 1 : -1
                    let role: Int
                    switch split.kind {
                    case .corner: role = sign
                    case .extremumX: role = d.dy >= 0 ? 2 : -2
                    case .extremumY: role = d.dx >= 0 ? 3 : -3
                    case .tangent: role = sign*4
                    case .inflection: role = sign*5
                    case .fitterJoint: role = 0
                    }
                    roles[index] = role
                }
            }
            let original = contour.points.map(placed)
            // Require a turn to persist over a physical neighbourhood. Smooth
            // rounded terminals and pixel staircases are not sharp landmarks.
            func neighbour(_ index: Int,_ direction: Int,_ distance: Double) -> Point2D {
                var point=original[index], walked=0.0, previous=index
                for step in 1..<original.count {
                    let next=(index+direction*step+original.count*2)%original.count
                    let length=original[previous].matchDistance(to:original[next])
                    if walked+length>=distance { return original[previous].interpolated(to:original[next],t:(distance-walked)/max(length,1e-12)) }
                    walked += length; previous=next; point=original[next]
                }
                return point
            }
            for (index,role) in roles where abs(role)==1 {
                func angle(_ radius: Double) -> Double {
                    let incoming=original[index]-neighbour(index,-1,radius), outgoing=neighbour(index,1,radius)-original[index]
                    return abs(atan2(incoming.cross(outgoing),incoming.dot(outgoing)))
                }
                let inner=angle(tolerance*6), outer=angle(tolerance*12)
                if inner<max(18,options.cornerThresholdDegrees)*Double.pi/180 || inner<outer*0.65 { roles[index]=role*4 }
            }
            guard original.allSatisfy({ $0.isFinite && abs($0.x)<=1e9 && abs($0.y)<=1e9 }) else { throw MasterMatchError.invalid("transformed boundary coordinates") }
            let kept = simplify(original, tolerance:tolerance/16, protected:Set(roles.keys))
            guard (3...4096).contains(kept.count) else { throw MasterMatchError.invalid("raster planning point limit") }
            let sign = m[0]*m[3]-m[1]*m[2] > 0 ? 1 : -1
            let spans = kept.indices.map { i in MatchSpan(curve:lineCubic(from:original[kept[i]],to:original[kept[(i+1)%kept.count]]),
                line:true,startSource:kept[i],controlSources:[nil,nil],smooth:abs(roles[kept[i]] ?? 0) != 1,
                featureRole:(roles[kept[i]] ?? 0)*sign) }
            return Boundary(ring:MatchRing(spans:spans),original:original)
        }
        // Marching-squares contours do not carry nonzero-fill winding policy.
        // Establish opposite outer/counter directions before shared planning.
        let depths = MatchGeometry.depths(boundaries.map(\.ring))
        for i in boundaries.indices {
            let wanted = depths[i] % 2 == 0 ? 1.0 : -1.0
            if boundaries[i].ring.area*wanted<0 {
                boundaries[i].ring = boundaries[i].ring.reversed()
                boundaries[i].reversedOriginal = true
            }
        }
        return Extracted(boundaries:boundaries,report:.init(masterID:input.id,
            sha256:SHA256.hash(data:input.imageData).map { String(format:"%02x",$0) }.joined(),
            sourceWidth:prepared.sourceWidth,sourceHeight:prepared.sourceHeight,transform:m,threshold:prepared.threshold,
            invert:prepared.invert,maximumBoundaryDeviation:0,options:options,
            contourOrder:[],startBoundaryPoints:[],reversedContours:[]))
    }

    private static func unique(_ values: [Double], anchors: [Double] = []) -> [Double] {
        // Nearby target landmarks may coincide with a reference knot. Prefer
        // the exact mandatory knot; never merge two distinct reference knots.
        let snapped = values.map { value in
            anchors.min(by:{ abs($0-value)<abs($1-value) }).flatMap {
                abs($0-value)<=1e-7 ? $0 : nil
            } ?? value
        } + anchors
        var result: [Double] = []
        for value in snapped.sorted() where result.last.map({ last in
            value-last > 1e-7 || (anchors.contains(value) && anchors.contains(last) && value>last)
        }) ?? true { result.append(value) }
        return result
    }
    private static func rasterConnections(_ input: MatchRing) -> MatchRing {
        var ring = input
        for i in ring.spans.indices where ring.spans[i].smooth {
            let a = ring.spans[(i+ring.spans.count-1)%ring.spans.count].curve.derivative(at:1)
            let b = ring.spans[i].curve.derivative(at:0)
            // A generated raster node has no source flag to preserve. Mark
            // smooth only where the fitted endpoint tangents support it.
            ring.spans[i].smooth = a.dot(b)>0 && abs(atan2(a.cross(b),a.dot(b)))<0.17
        }
        return ring
    }
    private static func withinEnvelope(_ input: MatchRing,bounds: Bounds,boundary: MatchRing,cuts: [Double],tolerance: Double) -> MatchRing {
        var ring=input
        for i in ring.spans.indices {
            let b=ring.spans[i].curve.bounds
            let y=b.minY<bounds.minY || b.maxY>bounds.maxY
            guard y else { continue }
            func bounded(_ p: Point2D) -> Point2D {
                .init(x:p.x,y:min(bounds.maxY,max(bounds.minY,p.y)))
            }
            let c=ring.spans[i].curve
            func candidate(_ fraction: Double) -> CubicBezier {
                CubicBezier(start:bounded(c.start),control1:c.control1.interpolated(to:bounded(c.control1),t:fraction),
                    control2:c.control2.interpolated(to:bounded(c.control2),t:fraction),end:bounded(c.end))
            }
            var lo=0.0, hi=1.0
            for _ in 0..<40 {
                let mid=(lo+hi)/2, b=candidate(mid).bounds
                let rounding=max(1,bounds.height)*Double.ulpOfOne*64
                if b.minY>=bounds.minY-rounding && b.maxY<=bounds.maxY+rounding { hi=mid }
                else { lo=mid }
            }
            let bounded=candidate(hi)
            ring.spans[i].curve=ring.spans[i].line ? bounded : MatchingCubicFitter.polish(bounded,
                points:MatchingStructureFitter.samples(boundary,start:cuts[i],end:cuts[i+1]),budget:tolerance*(15.0/16),
                verticalEnvelope:bounds,iterations:32)
        }
        return ring
    }
    private static func refineRawBoundary(_ input: MatchRing,points: [Point2D],bounds: Bounds,tolerance: Double) -> MatchRing {
        var ring=input,poly=points
        if polygonSignedArea(of:poly)*ring.area<0 { poly.reverse() }
        poly.append(poly[0])
        for i in ring.spans.indices where !ring.spans[i].line {
            let original=ring.spans[i].curve
            let samples=MatchBoundarySampling.span(poly,from:original.start,to:original.end)
            let proposed=MatchingCubicFitter.minimax(original,points:samples,budget:tolerance*0.75,verticalEnvelope:bounds)
            var candidate=ring;candidate.spans[i].curve=proposed
            if boundaryDeviation(points,candidate,tolerance:tolerance)<boundaryDeviation(points,ring,tolerance:tolerance) { ring=candidate }
        }
        return ring
    }
    private static func polishSmooth(_ input: MatchRing,other: MatchRing,boundary: [Point2D],tolerance: Double) -> MatchRing {
        var ring=input
        for i in ring.spans.indices where ring.spans[i].smooth {
            let previous=(i+ring.spans.count-1)%ring.spans.count
            guard !ring.spans[i].line, !ring.spans[previous].line else { continue }
            let incoming=ring.spans[previous].curve.end-ring.spans[previous].curve.control2
            let outgoing=ring.spans[i].curve.control1-ring.spans[i].curve.start
            guard let a=incoming.matchNormalized(), let b=outgoing.matchNormalized(), a.dot(b)>0,
                  let direction=(a+b).matchNormalized() else { continue }
            var candidate=ring
            candidate.spans[previous].curve.control2=candidate.spans[previous].curve.end+(-direction)*incoming.matchMagnitude
            candidate.spans[i].curve.control1=candidate.spans[i].curve.start+direction*outgoing.matchMagnitude
            let safe=[previous,i].allSatisfy { j in
                MatchGeometry.controlled(candidate.spans[j].curve) && (0...100).allSatisfy { step in
                    let f=Double(step)/100, x=candidate.spans[j].curve, y=other.spans[j].curve
                    return MatchGeometry.controlled(CubicBezier(start:x.start.interpolated(to:y.start,t:f),
                        control1:x.control1.interpolated(to:y.control1,t:f),control2:x.control2.interpolated(to:y.control2,t:f),end:x.end.interpolated(to:y.end,t:f)))
                }
            }
            if safe && boundaryDeviation(boundary,candidate,tolerance:tolerance)<=tolerance { ring=candidate }
        }
        return ring
    }
    private static func simplify(_ points: [Point2D], tolerance: Double, protected: Set<Int>) -> [Int] {
        var keep = protected.union([0,points.count/2,points.count])
        let input = points+[points[0]]
        func section(_ start: Int,_ end: Int) {
            var pending = [(start,end)]
            while let (start,end) = pending.popLast() {
            guard end > start+1 else { continue }
            let chord = [input[start],input[end]]
            let best = ((start+1)..<end).max { MatchGeometry.distance(input[$0],to:chord) < MatchGeometry.distance(input[$1],to:chord) }!
            if MatchGeometry.distance(input[best],to:chord)>tolerance {
                keep.insert(best); pending.append((best,end)); pending.append((start,best))
            }
            }
        }
        let anchors = keep.sorted()
        for (a,b) in zip(anchors,anchors.dropFirst()) { section(a,b) }
        return keep.filter { $0<points.count }.sorted()
    }



    /// A boundary knot is an initial correspondence, not a constraint that ink
    /// endpoints must lie exactly on its polyline. Center a failing line's signed
    /// residuals, sharing every displaced endpoint with both adjacent sections.
    /// Original boundary measurement and all geometry gates remain authoritative.


    private static func errorSplit(_ span: MatchSpan,boundary: MatchRing,start: Double,end: Double) -> Double {
        let fractions=boundary.fractions(), poly=MatchGeometry.flatten(MatchRing(spans:[span]),tolerance:0.01)
        let indices=boundary.spans.indices.filter { fractions[$0]>start+(end-start)*0.15 && fractions[$0]<end-(end-start)*0.15 }
        return indices.max { MatchGeometry.distance(boundary.spans[$0].curve.start,to:poly)<MatchGeometry.distance(boundary.spans[$1].curve.start,to:poly) }
            .map { fractions[$0] } ?? (start+end)/2
    }
    private static func prune(reference r: MatchRing,target t: MatchRing,cuts: inout [Double],targetCuts: inout [Double],
        mandatory: [Double],mode: RasterMatchMode,policy: ReferencePolicy,tolerance: Double) {
        guard cuts.count>4 else { return }
        var i=1
        while i<cuts.count-1 && cuts.count>4 {
            if mandatory.contains(where:{ abs($0-cuts[i])<1e-12 }) { i += 1; continue }
            let merged=MatchingStructureFitter.section(reference:r,target:t,start:cuts[i-1],end:cuts[i+1],targetStart:targetCuts[i-1],targetEnd:targetCuts[i+1],mode:mode,policy:policy,tolerance:tolerance)
            if merged.accepted { cuts.remove(at:i); targetCuts.remove(at:i) }
            else { i += 1 }
        }
    }


    private static func boundaryDeviation(_ points: [Point2D], _ ring: MatchRing, tolerance: Double) -> Double {
        let flatness = tolerance/32
        let vector = MatchGeometry.flatten(ring,tolerance:flatness), raster = points+[points[0]]
        return max(points.map { MatchGeometry.distance($0,to:vector) }.max() ?? 0,
                   vector.map { MatchGeometry.distance($0,to:raster) }.max() ?? 0)+flatness*2
    }
}
