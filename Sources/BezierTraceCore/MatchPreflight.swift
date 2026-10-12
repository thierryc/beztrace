// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

/// referenceImage, when supplied, is a caller-rendered silhouette of the reference,
/// placed with the same affine as matching. No target artwork is required.
public struct MatchPreflightRequest: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var unitsPerEm: Double
    public var reference: MatchMaster
    public var options: MasterMatchOptions
    public var rasterOptions: RasterMatchOptions
    public var referenceImage: MatchRasterInput?
    public init(unitsPerEm: Double = 1000, reference: MatchMaster,
                options: MasterMatchOptions? = nil, rasterOptions: RasterMatchOptions = .init(),
                referenceImage: MatchRasterInput? = nil) {
        self.unitsPerEm = unitsPerEm; self.reference = reference
        self.options = options ?? .init(fitTolerance:unitsPerEm/1000)
        self.rasterOptions = rasterOptions; self.referenceImage = referenceImage
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, unitsPerEm, reference, options, rasterOptions, referenceImage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        schemaVersion = try c.decode(Int.self,forKey:.schemaVersion)
        unitsPerEm = try c.decode(Double.self,forKey:.unitsPerEm)
        reference = try c.decode(MatchMaster.self,forKey:.reference)
        options = try c.decodeIfPresent(MasterMatchOptions.self,forKey:.options) ?? .init(fitTolerance:unitsPerEm/1000)
        rasterOptions = try c.decodeIfPresent(RasterMatchOptions.self,forKey:.rasterOptions) ?? .init()
        referenceImage = try c.decodeIfPresent(MatchRasterInput.self,forKey:.referenceImage)
    }
}

public struct ReferenceRasterPreflightReport: Codable, Sendable {
    public var masterID: String
    public var sha256: String
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var transform: [Double]
    public var threshold: UInt8
    public var invert: Bool
    public var options: RasterMatchOptions
}

public struct MatchPreflightResult: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var kind: String = "beztrace-match-preflight"
    public var engineVersion: String = BezierTraceVersion.engine
    public var eligible: Bool
    public var referenceHash: String
    public var referenceContours: Int
    public var referenceOnCurves: Int
    public var referenceNodes: Int
    public var rasterTopologyChecked: Bool
    public var rasterSource: ReferenceRasterPreflightReport?
    public var rasterContours: Int?
    public var referenceDepths: [Int]?
    public var rasterDepths: [Int]?
    public var diagnostics: [MatchDiagnostic]
    public var advisoryScanComplete: Bool
}

public enum MatchPreflight {
    public static func inspect(_ request: MatchPreflightRequest) throws -> MatchPreflightResult {
        let contours = request.reference.outline.contours, options = request.options
        guard request.schemaVersion == 1, request.unitsPerEm.isFinite, (16...16384).contains(request.unitsPerEm),
              !request.reference.id.isEmpty, request.reference.id.utf8.count <= 255,
              !contours.isEmpty, contours.count <= 64, contours.reduce(0,{$0+$1.nodes.count}) <= 4096,
              options.fitTolerance.isFinite, options.fitTolerance > 0, options.fitTolerance <= request.unitsPerEm/10 else {
            throw MasterMatchError.invalid("preflight version, UPM, reference, tolerance or resource limits")
        }
        try MatchNodeBudget.validate(options)
        try RasterMasterMatcher.validateRasterOptions(request.rasterOptions,mode:"reference-preflight")
        var rings: [MatchRing] = [], diagnostics: [MatchDiagnostic] = []
        for (i,contour) in contours.enumerated() {
            let context = MatchGeometryContext(stage:"input",role:"reference",masterID:request.reference.id,
                contour:i,existedBeforeFitting:true)
            do {
                let ring = try MatchRing(contour)
                rings.append(ring)
                try MatchGeometry.validate(ring,unitsPerEm:request.unitsPerEm,context:context)
            } catch let error as MasterMatchError {
                diagnostics.append(error.diagnostic ?? context.diagnostic(error.description))
            }
        }
        let onCurves = contours.reduce(0,{$0+$1.nodes.filter { $0.type != .offcurve }.count})
        let total = contours.reduce(0,{$0+$1.nodes.count})
        do { _ = try MatchNodeBudget.check(onCurves,referenceCount:onCurves,options:options,totalNodes:total) }
        catch { diagnostics.append(.init(code:"node-budget",message:String(describing:error),stage:"reference-preflight",role:"reference",masterID:request.reference.id)) }

        // Contact classification is advisory and bounded independently of validity.
        var remainingPairs = 250_000, complete = true
        if rings.count == contours.count && !diagnostics.contains(where:{$0.blocking}) {
            let epsilon = request.unitsPerEm/20000
            var edges: [MatchGeometry.DiagnosticEdge] = []
            for (i,ring) in rings.enumerated() {
                edges += MatchGeometry.diagnosticEdges(ring,tolerance:epsilon,contour:i)
                if edges.count > 16384 { complete = false; break }
            }
            if complete {
                scan: for i in edges.indices {
                    for j in edges.indices where j > i {
                        let a = edges[i], b = edges[j]
                        // Ordinary joins within a contour are not noteworthy contacts.
                        if a.location.contour == b.location.contour &&
                            (j == i+1 || (a.start == b.end && a.location.segment == 0)) { continue }
                        remainingPairs -= 1
                        if remainingPairs < 0 || diagnostics.count >= 64 { complete = false; break scan }
                        if max(a.start.x,a.end.x)+epsilon < min(b.start.x,b.end.x) ||
                            max(b.start.x,b.end.x)+epsilon < min(a.start.x,a.end.x) ||
                            max(a.start.y,a.end.y)+epsilon < min(b.start.y,b.end.y) ||
                            max(b.start.y,b.end.y)+epsilon < min(a.start.y,a.end.y) { continue }
                        guard let (classification,point) = MatchGeometry.contact(a,b,epsilon:epsilon) else { continue }
                        diagnostics.append(.init(code:"boundary-contact",message:"Advisory \(classification) on the flattened reference boundary",
                            stage:"reference-preflight",role:"reference",masterID:request.reference.id,
                            locations:[a.location,b.location],coordinates:[point.x,point.y],classification:classification,
                            existedBeforeFitting:true,approximationTolerance:epsilon,blocking:false))
                    }
                }
            }
        } else { complete = false }
        var source: ReferenceRasterPreflightReport?, count: Int?, depths: [Int]?, rasterDepths: [Int]?
        if let image = request.referenceImage {
            guard !image.id.isEmpty, image.id.utf8.count <= 255 else { throw MasterMatchError.invalid("referenceImage.id must contain 1...255 UTF-8 bytes") }
            let (boundary,report) = try RasterMasterMatcher.preflightBoundary(image,options:request.rasterOptions,tolerance:options.fitTolerance)
            source = .init(masterID:report.masterID,sha256:report.sha256,sourceWidth:report.sourceWidth,
                sourceHeight:report.sourceHeight,transform:report.transform,threshold:report.threshold,
                invert:report.invert,options:report.options)
            count = boundary.count; rasterDepths = MatchGeometry.depths(boundary)
            if rings.count == contours.count {
                depths = MatchGeometry.depths(rings)
                if contours.count != boundary.count || depths!.sorted() != rasterDepths!.sorted() {
                    diagnostics.append(.init(code:"reference-raster-topology",message:"Reference has \(contours.count) vector contours; rendered silhouette has \(boundary.count). Contour count or nesting differs; no contours are repaired or fabricated.",
                        stage:"reference-preflight",role:"reference",masterID:request.reference.id))
                }
            }
        }
        return .init(eligible:!diagnostics.contains(where:{$0.blocking}),referenceHash:try OutlineMatcher.hash(request.reference.outline),
            referenceContours:contours.count,referenceOnCurves:onCurves,referenceNodes:total,
            rasterTopologyChecked:request.referenceImage != nil && rings.count == contours.count,
            rasterSource:source,rasterContours:count,referenceDepths:depths,rasterDepths:rasterDepths,
            diagnostics:diagnostics,advisoryScanComplete:complete)
    }
}
