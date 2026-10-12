// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

public enum ReferencePolicy: String, Codable, Sendable { case fixed; case sharedSubdivision = "shared-subdivision" }

public struct MatchAxis: Codable, Equatable, Sendable {
    public var tag: String
    public var locations: [Double]
    public init(tag: String, locations: [Double]) { self.tag = tag; self.locations = locations }
}

public struct MatchMaster: Codable, Equatable, Sendable {
    public var id: String
    public var outline: Outline
    public init(id: String, outline: Outline) { self.id = id; self.outline = outline }
}

public struct MasterMatchOptions: Codable, Sendable {
    public var referencePolicy: ReferencePolicy
    /// Font units, not pixels. Defaults to one unit at 1000 UPM.
    public var fitTolerance: Double
    /// Reference-contour index -> input target-contour index; empty means automatic.
    public var contourPairs: [Int]
    /// Reference-contour index -> input target on-curve node index; -1 means automatic.
    public var startNodes: [Int]
    /// Review existing correspondence without reordering or changing structure.
    public var preserveStructure: Bool
    /// Additional on-curves across the entire glyph; zero is the safe default.
    public var maxAdditionalOnCurveNodes: Int
    /// Absolute ceiling across all contours, also used for joint raster tracing.
    public var maxOnCurveNodes: Int
    /// Includes off-curve handles; prevents degree elevation from hiding growth.
    public var maxNodes: Int
    public init(referencePolicy: ReferencePolicy = .fixed, fitTolerance: Double = 1,
                contourPairs: [Int] = [], startNodes: [Int] = [], preserveStructure: Bool = false,
                maxAdditionalOnCurveNodes: Int = 0, maxOnCurveNodes: Int = 64, maxNodes: Int = 64) {
        self.referencePolicy = referencePolicy; self.fitTolerance = fitTolerance
        self.contourPairs = contourPairs; self.startNodes = startNodes
        self.preserveStructure = preserveStructure
        self.maxAdditionalOnCurveNodes = maxAdditionalOnCurveNodes
        self.maxOnCurveNodes = maxOnCurveNodes
        self.maxNodes = maxNodes
    }
    enum CodingKeys: String, CodingKey { case referencePolicy, fitTolerance, contourPairs, startNodes, preserveStructure, maxAdditionalOnCurveNodes, maxOnCurveNodes, maxNodes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(referencePolicy: try c.decodeIfPresent(ReferencePolicy.self, forKey: .referencePolicy) ?? .fixed,
                  fitTolerance: try c.decodeIfPresent(Double.self, forKey: .fitTolerance) ?? 1,
                  contourPairs: try c.decodeIfPresent([Int].self, forKey: .contourPairs) ?? [],
                  startNodes: try c.decodeIfPresent([Int].self, forKey: .startNodes) ?? [],
                  preserveStructure: try c.decodeIfPresent(Bool.self, forKey: .preserveStructure) ?? false,
                  maxAdditionalOnCurveNodes: try c.decodeIfPresent(Int.self, forKey: .maxAdditionalOnCurveNodes) ?? 0,
                  maxOnCurveNodes: try c.decodeIfPresent(Int.self, forKey: .maxOnCurveNodes) ?? 64,
                  maxNodes: try c.decodeIfPresent(Int.self, forKey: .maxNodes) ?? 64)
    }
}

public struct MasterMatchRequest: Codable, Sendable {
    public var schemaVersion: Int
    public var unitsPerEm: Double
    public var axis: MatchAxis
    public var reference: MatchMaster
    public var target: MatchMaster
    public var options: MasterMatchOptions
    public init(unitsPerEm: Double = 1000, axis: MatchAxis, reference: MatchMaster,
                target: MatchMaster, options: MasterMatchOptions? = nil) {
        schemaVersion = 1; self.unitsPerEm = unitsPerEm; self.axis = axis
        self.reference = reference; self.target = target
        self.options = options ?? .init(fitTolerance: unitsPerEm / 1000)
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, unitsPerEm, axis, reference, target, options }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        unitsPerEm = try c.decode(Double.self, forKey: .unitsPerEm)
        axis = try c.decode(MatchAxis.self, forKey: .axis)
        reference = try c.decode(MatchMaster.self, forKey: .reference)
        target = try c.decode(MatchMaster.self, forKey: .target)
        options = try c.decodeIfPresent(MasterMatchOptions.self, forKey: .options) ?? .init(fitTolerance: unitsPerEm / 1000)
    }
}

public struct MatchContourReport: Codable, Sendable {
    public var referenceContour: Int
    public var targetContour: Int
    public var targetStartNode: Int
    public var targetReversed: Bool
    public var insertedReferenceNodes: Int
    public var insertedTargetNodes: Int
    public var maximumTargetDeviation: Double
    /// Original node indices; nil denotes a newly generated node/handle.
    public var referenceSourceNodes: [Int?]
    public var targetSourceNodes: [Int?]
    public var nodeIDs: [String]
}

public struct InterpolationIssue: Codable, Sendable {
    public var factor: Double
    public var contour: Int
    public var node: Int?
    public var message: String
    public var diagnostic: MatchDiagnostic? = nil
}

public struct InterpolationReport: Codable, Sendable {
    public var sampledOnly: Bool = true
    public var nativeHOIVerified: Bool = false
    public var sampleCount: Int
    public var maximumTangencyResidual: Double
    public var issues: [InterpolationIssue]
}

public struct MasterMatchResult: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var kind: String = "beztrace-master-set"
    public var pathDataVersion: Int = 2
    public var engineVersion: String = BezierTraceVersion.engine
    public var unitsPerEm: Double
    public var axis: MatchAxis
    public var reference: MatchMaster
    public var target: MatchMaster
    public var options: MasterMatchOptions
    public var sourceHashes: [String]
    public var sourceMasters: [MatchMaster]
    public var contours: [MatchContourReport]
    public var interpolation: InterpolationReport
    public var warnings: [String]
    public var rasterSources: [RasterMatchSourceReport]? = nil
    public var nodeBudget: MatchNodeBudgetReport? = nil
}

public enum MasterMatchError: Error, CustomStringConvertible {
    case invalid(String), topology(String), ambiguousContour(Int), ambiguousStart(Int)
    case fit(Int, String), geometry(String), nodeBudget(String)
    case invalidDiagnostic(MatchDiagnostic), geometryDiagnostic(MatchDiagnostic), fitDiagnostic(MatchDiagnostic)
    public var diagnostic: MatchDiagnostic? {
        switch self {
        case .invalidDiagnostic(let d), .geometryDiagnostic(let d), .fitDiagnostic(let d): return d
        default: return nil
        }
    }
    public var isInvalidRequest: Bool {
        switch self { case .invalid, .invalidDiagnostic: return true; default: return false }
    }
    public var description: String {
        switch self {
        case .invalidDiagnostic(let d): return "Invalid matching request: \(d.message)"
        case .fitDiagnostic(let d): return d.message
        case .geometryDiagnostic(let d):
            let location = d.locations?.map { "contour \($0.contour), segment \($0.segment)" }.joined(separator:" / ") ?? ""
            let role = [d.role,d.masterID].compactMap { $0 }.joined(separator:" ")
            return "Invalid matched geometry: \(d.message) (\(d.stage), \(role), \(location))"
        case .invalid(let s): return "Invalid matching request: \(s)"
        case .topology(let s): return "Topology mismatch: \(s)"
        case .ambiguousContour(let i): return "Ambiguous contour \(i); provide contourPairs explicitly"
        case .ambiguousStart(let i): return "Ambiguous start on contour \(i); provide startNodes explicitly"
        case .fit(let i, let s): return "Contour \(i): \(s). Try shared subdivision or revise the source"
        case .geometry(let s): return "Invalid matched geometry: \(s)"
        case .nodeBudget(let s): return "Point budget exceeded: \(s). Increase the point allowance explicitly, adjust fitting tolerance, or revise the source"
        }
    }
}

public enum MasterMatchSerializer {
    public static func json(_ result: MasterMatchResult, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return try encoder.encode(result)
    }
}
