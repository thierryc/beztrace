// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

public enum TraceProfile: String, Codable, Equatable, Sendable {
    case cleanGenerated = "clean-generated"
}

public enum DiagnosticLevel: String, Codable, Equatable, Sendable {
    case none
    case summary
}

public enum TraceThreshold: Codable, Equatable, Sendable {
    case automatic
    case fixed(UInt8)

    private enum CodingKeys: String, CodingKey { case method, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .method) {
        case "automatic": self = .automatic
        case "fixed": self = .fixed(try container.decode(UInt8.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "unknown threshold method"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode("automatic", forKey: .method)
        case .fixed(let value):
            try container.encode("fixed", forKey: .method)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct TraceOptions: Codable, Equatable, Sendable {
    public var profile: TraceProfile
    public var threshold: TraceThreshold
    public var invert: Bool
    public var minimumContourArea: Double
    public var accuracy: Double
    public var smoothing: Double
    public var cornerThresholdDegrees: Double
    public var grid: Int
    public var structureGrid: Int
    public var refineRaster: Bool
    public var rtlStart: Bool
    public var diagnostics: DiagnosticLevel

    public init(
        profile: TraceProfile = .cleanGenerated,
        threshold: TraceThreshold = .automatic,
        invert: Bool = false,
        minimumContourArea: Double = 100,
        accuracy: Double = 2,
        smoothing: Double = 1,
        cornerThresholdDegrees: Double = 12,
        grid: Int = 2,
        structureGrid: Int = 0,
        refineRaster: Bool = true,
        rtlStart: Bool = false,
        diagnostics: DiagnosticLevel = .none
    ) {
        self.profile = profile
        self.threshold = threshold
        self.invert = invert
        self.minimumContourArea = minimumContourArea
        self.accuracy = accuracy
        self.smoothing = smoothing
        self.cornerThresholdDegrees = cornerThresholdDegrees
        self.grid = grid
        self.structureGrid = structureGrid
        self.refineRaster = refineRaster
        self.rtlStart = rtlStart
        self.diagnostics = diagnostics
    }
}

public struct Rect: Codable, Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        minX = try values.decode(Double.self)
        minY = try values.decode(Double.self)
        maxX = try values.decode(Double.self)
        maxY = try values.decode(Double.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "rect requires four numbers")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(minX)
        try values.encode(minY)
        try values.encode(maxX)
        try values.encode(maxY)
    }
}

public enum PlacementSourceBox: Equatable, Sendable {
    case canvas
    case ink
    case rectangle(Rect)
}

public enum HorizontalMetricsMode: Equatable, Sendable {
    case sidebearings(left: Double, right: Double)
    case advance(width: Double, left: Double)
    case centered(advance: Double)
}

public struct PlacementOptions: Equatable, Sendable {
    public var sourceBox: PlacementSourceBox
    public var targetYMin: Double
    public var targetYMax: Double
    public var horizontalMode: HorizontalMetricsMode
    public var grid: Int

    public init(
        sourceBox: PlacementSourceBox = .ink,
        targetYMin: Double,
        targetYMax: Double,
        horizontalMode: HorizontalMetricsMode,
        grid: Int = 2
    ) {
        self.sourceBox = sourceBox
        self.targetYMin = targetYMin
        self.targetYMax = targetYMax
        self.horizontalMode = horizontalMode
        self.grid = grid
    }
}

public struct TraceRequest: Equatable, Sendable {
    public var imageData: Data
    public var options: TraceOptions
    public var placement: PlacementOptions?

    public init(
        imageData: Data,
        options: TraceOptions = TraceOptions(),
        placement: PlacementOptions? = nil
    ) {
        self.imageData = imageData
        self.options = options
        self.placement = placement
    }
}

public enum NodeKind: String, Codable, Equatable, Sendable {
    case line
    case curve
    case offcurve
}

public struct Node: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var type: NodeKind
    public var smooth: Bool

    public init(x: Double, y: Double, type: NodeKind, smooth: Bool = false) {
        self.x = x
        self.y = y
        self.type = type
        self.smooth = smooth
    }
}

public struct Contour: Codable, Equatable, Sendable {
    public var closed: Bool
    public var nodes: [Node]

    public init(closed: Bool = true, nodes: [Node]) {
        self.closed = closed
        self.nodes = nodes
    }
}

public struct Outline: Codable, Equatable, Sendable {
    public var contours: [Contour]

    public init(contours: [Contour]) {
        self.contours = contours
    }
}

public enum SourceImageFormat: String, Codable, Equatable, Sendable {
    case png
    case jpeg
}

public struct EngineReport: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let portSourceRevision: String
}

public struct SourceReport: Codable, Equatable, Sendable {
    public let sha256: String
    public let format: SourceImageFormat
    public let width: Int
    public let height: Int
    public let usedAlphaMask: Bool
}

public enum ResolvedThresholdMethod: String, Codable, Equatable, Sendable {
    case automatic
    case fixed
}

public struct ResolvedTraceOptions: Codable, Equatable, Sendable {
    public let profile: TraceProfile
    public let thresholdMethod: ResolvedThresholdMethod
    public let threshold: Int
    public let invert: Bool
    public let minimumContourArea: Double
    public let targetHeight: Double
    public let accuracy: Double
    public let smoothing: Double
    public let cornerThresholdDegrees: Double
    public let grid: Int
    public let structureGrid: Int
    public let refineRaster: Bool
    public let rtlStart: Bool
    public let diagnostics: DiagnosticLevel
}

public struct PlacementReport: Codable, Equatable, Sendable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let inkBoundsPixels: Rect
    public let sourceBoundsPixels: Rect
    public let targetYMin: Double
    public let targetYMax: Double
    public let scale: Double
    public let translationX: Double
    public let translationY: Double
    public let finalBounds: Rect
    public let advanceWidth: Double
    public let leftSideBearing: Double
    public let rightSideBearing: Double
    public let outOfTarget: Bool
}

public struct OutlineStatistics: Codable, Equatable, Sendable {
    public let contourCount: Int
    public let nodeCount: Int
    public let lineCount: Int
    public let curveCount: Int
    public let offCurveCount: Int
}

public struct TraceResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let engine: EngineReport
    public let source: SourceReport
    public let resolvedOptions: ResolvedTraceOptions
    public let pathDataVersion: Int
    public let metadataPolicy: String
    public let outline: Outline
    public let bounds: Rect?
    public let placement: PlacementReport?
    public let statistics: OutlineStatistics
    public let timingsMs: [String: Double]
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, engine, source, resolvedOptions, pathDataVersion
        case metadataPolicy, paths, bounds, placement, statistics, timingsMs, warnings
    }

    public init(
        schemaVersion: Int = 1,
        engine: EngineReport,
        source: SourceReport,
        resolvedOptions: ResolvedTraceOptions,
        pathDataVersion: Int = 2,
        metadataPolicy: String = "preserve",
        outline: Outline,
        bounds: Rect?,
        placement: PlacementReport?,
        statistics: OutlineStatistics,
        timingsMs: [String: Double] = [:],
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.engine = engine
        self.source = source
        self.resolvedOptions = resolvedOptions
        self.pathDataVersion = pathDataVersion
        self.metadataPolicy = metadataPolicy
        self.outline = outline
        self.bounds = bounds
        self.placement = placement
        self.statistics = statistics
        self.timingsMs = timingsMs
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        engine = try container.decode(EngineReport.self, forKey: .engine)
        source = try container.decode(SourceReport.self, forKey: .source)
        resolvedOptions = try container.decode(ResolvedTraceOptions.self, forKey: .resolvedOptions)
        pathDataVersion = try container.decode(Int.self, forKey: .pathDataVersion)
        metadataPolicy = try container.decode(String.self, forKey: .metadataPolicy)
        outline = Outline(contours: try container.decode([Contour].self, forKey: .paths))
        bounds = try container.decodeIfPresent(Rect.self, forKey: .bounds)
        placement = try container.decodeIfPresent(PlacementReport.self, forKey: .placement)
        statistics = try container.decode(OutlineStatistics.self, forKey: .statistics)
        timingsMs = try container.decode([String: Double].self, forKey: .timingsMs)
        warnings = try container.decode([String].self, forKey: .warnings)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(engine, forKey: .engine)
        try container.encode(source, forKey: .source)
        try container.encode(resolvedOptions, forKey: .resolvedOptions)
        try container.encode(pathDataVersion, forKey: .pathDataVersion)
        try container.encode(metadataPolicy, forKey: .metadataPolicy)
        try container.encode(outline.contours, forKey: .paths)
        try container.encodeIfPresent(bounds, forKey: .bounds)
        try container.encodeIfPresent(placement, forKey: .placement)
        try container.encode(statistics, forKey: .statistics)
        try container.encode(timingsMs, forKey: .timingsMs)
        try container.encode(warnings, forKey: .warnings)
    }
}

public enum TraceError: Error, Equatable, Sendable {
    case invalidOptions(String)
    case invalidPlacement(String)
    case emptyInput
    case encodedInputTooLarge(actual: Int, limit: Int)
    case malformedImage
    case unsupportedImageFormat(String)
    case decodedImageTooLarge(width: Int, height: Int, limit: Int)
    case noContours
    case invalidGeometry(String)
    case serialization(String)
    case internalInvariant(String)
}

extension TraceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidOptions(let message): "invalid options: \(message)"
        case .invalidPlacement(let message): "invalid placement: \(message)"
        case .emptyInput: "input is empty"
        case .encodedInputTooLarge(let actual, let limit):
            "encoded input is too large (\(actual) bytes; limit \(limit))"
        case .malformedImage: "input is not a valid supported image"
        case .unsupportedImageFormat(let format): "unsupported image format: \(format)"
        case .decodedImageTooLarge(let width, let height, let limit):
            "decoded image is too large (\(width)x\(height); limit \(limit)x\(limit))"
        case .noContours: "image contains no traceable contours"
        case .invalidGeometry(let message): "invalid traced geometry: \(message)"
        case .serialization(let message): "serialization failed: \(message)"
        case .internalInvariant(let message): "internal invariant failed: \(message)"
        }
    }
}
