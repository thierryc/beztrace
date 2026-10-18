// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

/// File adapters and library clients share the same defaults. Missing limits
/// never authorize rebuilding an existing reference or adding structure.
public struct PairMatchConfiguration: Codable, Sendable {
    public var referencePolicy: ReferencePolicy?
    public var fitTolerance: Double?
    public var maxAdditionalOnCurveNodes: Int?
    public var maxOnCurveNodes: Int?
    public var maxNodes: Int?
    public var contourPairs: [Int]?
    public var startNodes: [Int]?

    public init(referencePolicy: ReferencePolicy? = nil, fitTolerance: Double? = nil,
                maxAdditionalOnCurveNodes: Int? = nil, maxOnCurveNodes: Int? = nil,
                maxNodes: Int? = nil, contourPairs: [Int]? = nil, startNodes: [Int]? = nil) {
        self.referencePolicy=referencePolicy; self.fitTolerance=fitTolerance
        self.maxAdditionalOnCurveNodes=maxAdditionalOnCurveNodes
        self.maxOnCurveNodes=maxOnCurveNodes; self.maxNodes=maxNodes
        self.contourPairs=contourPairs; self.startNodes=startNodes
    }

    public func resolved(reference: PairInput, unitsPerEm: Double) throws -> MasterMatchOptions {
        func invalid(_ field: String,_ message: String) -> MasterMatchError {
            .invalidOption(field:field,message:message)
        }
        let policy=referencePolicy ?? (reference.vector == nil ? .sharedSubdivision : .fixed)
        if reference.vector == nil && policy == .fixed {
            throw invalid("options.referencePolicy","Two images have no vector to keep fixed; use shared-subdivision with absolute limits.")
        }
        if policy == .fixed && (maxAdditionalOnCurveNodes ?? 0)>0 {
            throw invalid("options.maxAdditionalOnCurveNodes","Fixed reference cannot add knots. Choose shared-subdivision and explicit absolute limits to permit shape-preserving splits.")
        }
        if reference.vector == nil || policy == .sharedSubdivision {
            if maxOnCurveNodes == nil { throw invalid("options.maxOnCurveNodes","An absolute on-curve limit is required for joint planning or shared subdivision.") }
            if maxNodes == nil { throw invalid("options.maxNodes","An absolute total-node limit including cubic handles is required for joint planning or shared subdivision.") }
        }
        let contours=reference.vector?.outline.contours ?? []
        let on=contours.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count }
        let total=contours.reduce(0) { $0+$1.nodes.count }
        let options=MasterMatchOptions(referencePolicy:policy,fitTolerance:fitTolerance ?? unitsPerEm/1000,
            contourPairs:contourPairs ?? [],startNodes:startNodes ?? [],
            maxAdditionalOnCurveNodes:maxAdditionalOnCurveNodes ?? 0,
            maxOnCurveNodes:maxOnCurveNodes ?? on,maxNodes:maxNodes ?? total)
        try MatchNodeBudget.validate(options)
        return options
    }
}
