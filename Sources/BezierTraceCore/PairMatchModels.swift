// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

public enum PairStrategy: String, Codable, Sendable { case direct, smart; case retraceTarget="retrace-target", retraceBoth="retrace-both" }
public enum PairInput: Sendable {
    case outline(MatchMaster), image(MatchRasterInput)
    public var id: String { switch self { case .outline(let m):return m.id;case .image(let m):return m.id } }
    var vector: MatchMaster? { if case .outline(let m)=self { return m };return nil }
}
public struct PairRenderReceipt: Codable, Sendable {
    public var masterID: String
    public var sha256: String
    public var transform: [Double]
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var unitsPerPixel: Double
    public var paddingPixels: Int
    public var fillRule: String = "nonzero"
}
public struct PairEnvelopeAdjustment: Codable, Sendable {
    public var masterID: String
    public var previousYBounds: [Double]
    public var fittedYBounds: [Double]
    public var scaleY: Double
    public var translateY: Double
    public var method: String? = nil
}
public struct PairCandidateReport: Codable, Sendable {
    public var route: String
    public var accepted: Bool
    public var refusal: String? = nil
    public var diagnostic: MatchDiagnostic? = nil
    public var sourceDeviations: [PairDeviation] = []
    public var onCurveNodes: Int? = nil
    public var totalNodes: Int? = nil
    public var excessSmoothJoinResidual: Double? = nil
    public var referenceUnchanged: Bool? = nil
    public var targetUnchanged: Bool? = nil
    public var renderedSources: [PairRenderReceipt] = []
    /// Fitted coordinates only; source placement remains unchanged.
    public var envelopeAdjustments: [PairEnvelopeAdjustment] = []
}
public struct PairComparisonReport: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var kind: String = "beztrace-pair-comparison"
    public var engineVersion: String = BezierTraceVersion.engine
    public var strategy: PairStrategy
    public var options: MasterMatchOptions
    public var sourceHashes: [String]
    public var sourceOutlines: [MatchMaster]
    public var candidates: [PairCandidateReport]
    public var recommendedRoute: String?
    public var reasons: [String]
    public var sampledOnly: Bool = true
    public var nativeHOIVerified: Bool = false
}
public struct PairMatchOutput: Sendable {
    public var report: PairComparisonReport
    public var results: [String: MasterMatchResult]
    public var renders: [String: Data]
}
