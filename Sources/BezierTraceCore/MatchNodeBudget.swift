// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

public struct MatchNodeBudgetReport: Codable, Sendable {
    public var referenceOnCurves: Int?
    public var resultOnCurves: Int
    public var addedOnCurves: Int?
    public var allowedAdditional: Int
    public var maximumOnCurves: Int
    public var totalNodes: Int?
    public var maximumNodes: Int
}

enum MatchNodeBudget {
    static func validate(_ options: MasterMatchOptions) throws {
        for (field,value,range) in [("maxAdditionalOnCurveNodes",options.maxAdditionalOnCurveNodes,0...1024),
                                   ("maxOnCurveNodes",options.maxOnCurveNodes,3...1024),
                                   ("maxNodes",options.maxNodes,3...4096)] where !range.contains(value) {
            throw MasterMatchError.invalidDiagnostic(.init(code:"invalid-option",
                message:"options.\(field) provided \(value); expected \(range.lowerBound)...\(range.upperBound)",
                stage:"request-validation",field:"options."+field,providedValue:String(value),
                allowedRange:[Double(range.lowerBound),Double(range.upperBound)]))
        }
    }
    static func limit(_ options: MasterMatchOptions, referenceCount: Int?) -> Int {
        min(options.maxNodes,options.maxOnCurveNodes, referenceCount.map { $0+options.maxAdditionalOnCurveNodes } ?? options.maxOnCurveNodes)
    }
    static func check(_ count: Int, referenceCount: Int?, options: MasterMatchOptions, totalNodes: Int? = nil, detail: String = "") throws -> MatchNodeBudgetReport {
        let cap = limit(options,referenceCount:referenceCount)
        guard count<=cap else {
            throw MasterMatchError.nodeBudget("\(count) on-curves required; limit \(cap) across the glyph"+(detail.isEmpty ? "" : "; "+detail))
        }
        if let totalNodes, totalNodes>options.maxNodes {
            throw MasterMatchError.nodeBudget("\(totalNodes) total nodes including handles; ceiling \(options.maxNodes)"+(detail.isEmpty ? "" : "; "+detail))
        }
        return .init(referenceOnCurves:referenceCount,resultOnCurves:count,
            addedOnCurves:referenceCount.map { max(0,count-$0) },allowedAdditional:options.maxAdditionalOnCurveNodes,
            maximumOnCurves:options.maxOnCurveNodes,totalNodes:totalNodes,maximumNodes:options.maxNodes)
    }
}
