// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

extension MasterMatchError {
    public static func invalidOption(field: String,message: String) -> MasterMatchError {
        .invalidDiagnostic(.init(code:"invalid-option",message:message,stage:"request-validation",field:field))
    }
}

/// Diagnostic evidence only. It never changes geometry or acceptance thresholds.
public struct MatchDiagnostic: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var stage: String
    public var role: String?
    public var masterID: String?
    public var mode: String?
    public var field: String?
    public var providedValue: String?
    public var allowedRange: [Double]?
    public var locations: [MatchDiagnosticLocation]?
    public var coordinates: [Double]?
    public var classification: String?
    public var existedBeforeFitting: Bool?
    public var interpolationFactor: Double?
    /// Coordinates/classification are polyline evidence, not exact cubic certification.
    public var approximationTolerance: Double?
    public var section: Int? = nil
    public var measuredDeviation: Double? = nil
    public var allowedDeviation: Double? = nil
    public var cause: String? = nil
    public var boundarySpan: MatchBoundarySpan? = nil
    public var blocking: Bool = true
}

public struct MatchBoundarySpan: Codable, Equatable, Sendable {
    public var contour: Int
    /// Raw extracted boundary point IDs, not reduced selector indices.
    public var startPoint: Int
    public var endPoint: Int
    public var fractions: [Double]
}

public struct MatchDiagnosticLocation: Codable, Equatable, Sendable {
    public var contour: Int
    public var segment: Int
    public var startNode: Int?
    public var endNode: Int?
    public var parameterRange: [Double]
}

struct MatchGeometryContext {
    var stage: String = "geometry-validation"
    var role: String? = nil
    var masterID: String? = nil
    var contour: Int = 0
    var existedBeforeFitting: Bool? = nil
    var interpolationFactor: Double? = nil

    func diagnostic(_ message: String, code: String = "invalid-geometry") -> MatchDiagnostic {
        .init(code: code, message: message, stage: stage, role: role, masterID: masterID,
              existedBeforeFitting: existedBeforeFitting, interpolationFactor: interpolationFactor)
    }
}
