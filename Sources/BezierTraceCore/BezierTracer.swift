// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import CryptoKit
import Foundation

public enum BezierTraceVersion {
    public static let engine = "0.1.0"
    public static let schema = 1
    public static let pathData = 2
    public static let portSourceRevision = "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
}

public enum BezierTracer {
    public static func trace(_ request: TraceRequest) throws -> TraceResult {
        try validate(request.options)
        if let placement = request.placement { try PlacementEngine.validate(placement) }
        let started = DispatchTime.now().uptimeNanoseconds
        let rasterOptions = RasterPreparationOptions(
            threshold: request.options.threshold.rasterMethod,
            invert: request.options.invert,
            targetHeight: 1088,
            minimumContourArea: request.options.minimumContourArea
        )
        let prepared: PreparedRaster
        do {
            prepared = try RasterPreparer.prepare(data: request.imageData, options: rasterOptions)
        } catch {
            throw map(error)
        }
        let placementPlan = try request.placement.map {
            try PlacementEngine.plan(prepared: prepared, options: $0)
        }
        let targetHeight = placementPlan?.targetHeight ?? 1088
        var configuration = TraceConfiguration.capturedDefaults
        configuration.targetHeight = targetHeight
        configuration.fitAccuracy = request.options.accuracy
        configuration.smoothing = request.options.smoothing
        configuration.cornerThresholdDegrees = request.options.cornerThresholdDegrees
        configuration.refineRaster = request.options.refineRaster
        configuration.grid = request.options.grid
        configuration.structureGrid = request.options.structureGrid

        let internalResult: InternalTraceResult
        do {
            internalResult = try ContourPipeline.traceValidated(
                prepared: prepared,
                configuration: configuration,
                rasterOptions: rasterOptions
            )
        } catch {
            throw map(error)
        }
        var outline = Outline(validated: internalResult.outline)
        outline.normalizeStarts(rtl: request.options.rtlStart)
        let placementReport: PlacementReport?
        if let placement = request.placement, let placementPlan {
            let positioned = try PlacementEngine.position(
                outline: outline,
                prepared: prepared,
                options: placement,
                plan: placementPlan
            )
            outline = positioned.0
            placementReport = positioned.1
        } else {
            placementReport = nil
        }
        guard outline.contours.allSatisfy({ $0.closed && !$0.nodes.isEmpty }),
              outline.contours.flatMap(\.nodes).allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { throw TraceError.internalInvariant("validated outline conversion failed") }

        let statistics = OutlineStatistics(outline: outline)
        let timing: [String: Double]
        if request.options.diagnostics == .summary {
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            timing = ["total": Double(elapsed) / 1_000_000]
        } else {
            timing = [:]
        }
        let warnings = placementReport?.outOfTarget == true
            ? ["placed outline extends outside the requested target band"]
            : []
        return TraceResult(
            engine: EngineReport(
                name: "beztrace",
                version: BezierTraceVersion.engine,
                portSourceRevision: BezierTraceVersion.portSourceRevision
            ),
            source: SourceReport(
                sha256: SHA256.hash(data: request.imageData).map { String(format: "%02x", $0) }.joined(),
                format: prepared.sourceFormat == .png ? .png : .jpeg,
                width: prepared.sourceWidth,
                height: prepared.sourceHeight,
                usedAlphaMask: prepared.usedAlphaMask
            ),
            resolvedOptions: ResolvedTraceOptions(
                profile: request.options.profile,
                thresholdMethod: request.options.threshold.resolvedMethod,
                threshold: Int(prepared.threshold),
                invert: request.options.invert,
                minimumContourArea: request.options.minimumContourArea,
                targetHeight: targetHeight,
                accuracy: request.options.accuracy,
                smoothing: request.options.smoothing,
                cornerThresholdDegrees: request.options.cornerThresholdDegrees,
                grid: request.options.grid,
                structureGrid: request.options.structureGrid,
                refineRaster: request.options.refineRaster,
                rtlStart: request.options.rtlStart,
                diagnostics: request.options.diagnostics
            ),
            outline: outline,
            bounds: outline.tightBounds,
            placement: placementReport,
            statistics: statistics,
            timingsMs: timing,
            warnings: warnings
        )
    }

    private static func validate(_ options: TraceOptions) throws {
        guard options.minimumContourArea.isFinite, options.minimumContourArea >= 0 else {
            throw TraceError.invalidOptions("minimum contour area must be finite and zero or greater")
        }
        guard options.accuracy.isFinite, options.accuracy > 0 else {
            throw TraceError.invalidOptions("accuracy must be finite and greater than zero")
        }
        guard options.smoothing.isFinite, options.smoothing > 0 else {
            throw TraceError.invalidOptions("smoothing must be finite and greater than zero")
        }
        guard options.cornerThresholdDegrees.isFinite,
              options.cornerThresholdDegrees > 0,
              options.cornerThresholdDegrees < 180
        else { throw TraceError.invalidOptions("corner threshold must be between zero and 180 degrees") }
        guard options.grid >= 0, options.structureGrid >= 0 else {
            throw TraceError.invalidOptions("grids must be zero or greater")
        }
    }

    private static func map(_ error: Error) -> TraceError {
        guard let error = error as? CoreError else {
            return .internalInvariant(String(describing: error))
        }
        switch error {
        case .emptyInput: return .emptyInput
        case .encodedInputTooLarge(let actual, let limit):
            return .encodedInputTooLarge(actual: actual, limit: limit)
        case .malformedImage: return .malformedImage
        case .unsupportedImageFormat(let format): return .unsupportedImageFormat(format)
        case .decodedImageTooLarge(let width, let height, let limit):
            return .decodedImageTooLarge(width: width, height: height, limit: limit)
        case .noContours: return .noContours
        case .invalidOptions: return .invalidOptions("resolved internal options are invalid")
        case .nonFiniteGeometry: return .invalidGeometry("non-finite coordinate")
        case .invalidClosure(let contour): return .invalidGeometry("contour \(contour) is not closed")
        case .degenerateSegment(let contour, let segment):
            return .invalidGeometry("contour \(contour) segment \(segment) is degenerate")
        case .invalidWinding(let contour): return .invalidGeometry("contour \(contour) has invalid winding")
        case .selfIntersection(let contour): return .invalidGeometry("contour \(contour) self-intersects")
        case .handleReachExceeded(let contour, let segment):
            return .invalidGeometry("contour \(contour) segment \(segment) has uncontrolled handles")
        case .pointLimitExceeded(let contour, let actual, let limit):
            return .invalidGeometry("contour \(contour) has \(actual) points; limit \(limit)")
        case .invalidDimensions(let width, let height):
            return .internalInvariant("invalid raster dimensions \(width)x\(height)")
        case .invalidPixelStorage(let expected, let actual):
            return .internalInvariant("invalid pixel storage \(actual); expected \(expected)")
        case .pixelBufferAllocationFailed: return .internalInvariant("pixel buffer allocation failed")
        }
    }
}

private extension TraceThreshold {
    var rasterMethod: ThresholdMethod {
        switch self {
        case .automatic: .otsu
        case .fixed(let value): .fixed(value)
        }
    }

    var resolvedMethod: ResolvedThresholdMethod {
        switch self {
        case .automatic: .automatic
        case .fixed: .fixed
        }
    }
}

private extension Outline {
    init(validated: ValidatedOutline) {
        self.init(contours: validated.contours.map { contour in
            Contour(nodes: contour.points.map { point in
                let kind: NodeKind
                switch point.kind {
                case .line: kind = .line
                case .curve: kind = .curve
                case .offCurve: kind = .offcurve
                }
                return Node(
                    x: point.position.x,
                    y: point.position.y,
                    type: kind,
                    smooth: point.smooth
                )
            })
        })
    }
}

private extension OutlineStatistics {
    init(outline: Outline) {
        let nodes = outline.contours.flatMap(\.nodes)
        self.init(
            contourCount: outline.contours.count,
            nodeCount: nodes.count,
            lineCount: nodes.filter { $0.type == .line }.count,
            curveCount: nodes.filter { $0.type == .curve }.count,
            offCurveCount: nodes.filter { $0.type == .offcurve }.count
        )
    }
}
