// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import BezierTraceCore
import Foundation

struct CLIRunResult: Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

enum CLIApplication {
    private enum OutputFormat: String {
        case json
        case svg

        var fileExtension: String { rawValue }
    }

    private enum Command {
        case trace
        case batch
        case inspect
    }

    private struct ParsedCommand {
        let command: Command
        let inputs: [String]
        let format: OutputFormat
        let output: String?
        let outputDirectory: String?
        let svgTransformMode: SVGTransformMode
        let options: TraceOptions
        let placement: PlacementOptions?
    }

    private struct Failure: Error {
        let code: Int32
        let type: String
        let message: String
    }

    private struct ErrorEnvelope: Encodable {
        struct Detail: Encodable { let type: String; let message: String }
        let schemaVersion = 1
        let exitCode: Int32
        let error: Detail
    }

    static func run(arguments: [String], standardInput: Data = Data()) -> CLIRunResult {
        let jsonErrors = arguments.contains("--json-errors")
        do {
            if arguments == ["--version"] {
                return success(output: Data("beztrace \(BezierTraceVersion.engine)\n".utf8))
            }
            if arguments == ["--help"] || arguments == ["help"] {
                return success(output: Data(help.utf8))
            }
            let parsed = try parse(arguments)
            switch parsed.command {
            case .trace, .inspect:
                return try executeSingle(parsed, standardInput: standardInput)
            case .batch:
                return try executeBatch(parsed)
            }
        } catch let failure as Failure {
            return failed(failure, json: jsonErrors)
        } catch let error as TraceError {
            return failed(failure(for: error), json: jsonErrors)
        } catch {
            return failed(
                Failure(code: 7, type: "internal", message: String(describing: error)),
                json: jsonErrors
            )
        }
    }

    private static func executeSingle(
        _ parsed: ParsedCommand,
        standardInput: Data
    ) throws -> CLIRunResult {
        let input = parsed.inputs[0]
        let data = try readInput(input, standardInput: standardInput)
        let result = try BezierTracer.trace(TraceRequest(
            imageData: data,
            options: parsed.options,
            placement: parsed.placement
        ))
        let encoded = try serialize(
            result,
            format: parsed.format,
            svgTransformMode: parsed.svgTransformMode
        )
        if let output = parsed.output {
            try write(encoded, to: output)
            return success()
        }
        return success(output: encoded)
    }

    private static func executeBatch(_ parsed: ParsedCommand) throws -> CLIRunResult {
        guard let outputDirectory = parsed.outputDirectory else {
            throw Failure(code: 2, type: "argument", message: "batch requires --output-dir")
        }
        guard parsed.inputs.count <= 64 else {
            throw Failure(code: 2, type: "argument", message: "batch accepts at most 64 inputs")
        }
        var records: [(url: URL, data: Data)] = []
        var names: Set<String> = []
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        for input in parsed.inputs {
            guard input != "-" else {
                throw Failure(code: 2, type: "argument", message: "batch input must be a local path")
            }
            let stem = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else {
                throw Failure(code: 2, type: "argument", message: "batch input has no output name: \(input)")
            }
            let name = "\(stem).\(parsed.format.fileExtension)"
            guard names.insert(name).inserted else {
                throw Failure(code: 2, type: "argument", message: "batch output name collision: \(name)")
            }
            let source = try readInput(input, standardInput: Data())
            let result = try BezierTracer.trace(TraceRequest(
                imageData: source,
                options: parsed.options,
                placement: parsed.placement
            ))
            records.append((
                directory.appendingPathComponent(name),
                try serialize(
                    result,
                    format: parsed.format,
                    svgTransformMode: parsed.svgTransformMode
                )
            ))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for record in records { try record.data.write(to: record.url, options: .atomic) }
        } catch {
            throw Failure(code: 6, type: "output", message: "cannot write batch output: \(error.localizedDescription)")
        }
        return success()
    }

    private static func serialize(
        _ result: TraceResult,
        format: OutputFormat,
        svgTransformMode: SVGTransformMode
    ) throws -> Data {
        switch format {
        case .json:
            var data = try TraceSerializer.json(result)
            data.append(0x0A)
            return data
        case .svg:
            return Data(try TraceSerializer.svg(result, transformMode: svgTransformMode).utf8)
        }
    }

    private static func readInput(_ input: String, standardInput: Data) throws -> Data {
        if input == "-" { return standardInput }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: input), options: [.mappedIfSafe])
        } catch {
            throw Failure(code: 3, type: "input", message: "cannot read input: \(input)")
        }
    }

    private static func write(_ data: Data, to path: String) throws {
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw Failure(code: 6, type: "output", message: "cannot write output: \(path)")
        }
    }

    private static func parse(_ original: [String]) throws -> ParsedCommand {
        guard let commandName = original.first else {
            throw Failure(code: 2, type: "argument", message: "missing command")
        }
        let command: Command
        switch commandName {
        case "trace": command = .trace
        case "batch": command = .batch
        case "inspect": command = .inspect
        default: throw Failure(code: 2, type: "argument", message: "unknown command: \(commandName)")
        }

        var inputs: [String] = []
        var format: OutputFormat?
        var output: String?
        var outputDirectory: String?
        var svgTransformMode: SVGTransformMode = .bake
        var svgTransformWasSet = false
        var threshold: TraceThreshold = .automatic
        var invert = false
        var accuracy = 2.0
        var smoothing = 1.0
        var cornerThreshold = 12.0
        var minimumContourArea = 100.0
        var grid = 2
        var structureGrid = 0
        var refineRaster = true
        var rtlStart = false
        var diagnostics: DiagnosticLevel = .none
        var targetYMin: Double?
        var targetYMax: Double?
        var sourceBox = PlacementSourceBox.ink
        var sourceBoxWasSet = false
        var lsb: Double?
        var rsb: Double?
        var advance: Double?
        var centeredAdvance: Double?
        var placementGrid: Int?
        var index = 1

        func value(after option: String) throws -> String {
            guard index + 1 < original.count else {
                throw Failure(code: 2, type: "argument", message: "\(option) requires a value")
            }
            index += 1
            return original[index]
        }
        func double(_ value: String, option: String) throws -> Double {
            guard let parsed = Double(value), parsed.isFinite else {
                throw Failure(code: 2, type: "argument", message: "invalid value for \(option): \(value)")
            }
            return parsed
        }
        func integer(_ value: String, option: String) throws -> Int {
            guard let parsed = Int(value) else {
                throw Failure(code: 2, type: "argument", message: "invalid value for \(option): \(value)")
            }
            return parsed
        }

        while index < original.count {
            let argument = original[index]
            switch argument {
            case "--json-errors": break
            case "--format":
                let raw = try value(after: argument)
                guard let parsed = OutputFormat(rawValue: raw) else {
                    throw Failure(code: 2, type: "argument", message: "format must be json or svg")
                }
                format = parsed
            case "--output": output = try value(after: argument)
            case "--output-dir": outputDirectory = try value(after: argument)
            case "--svg-transform":
                let raw = try value(after: argument)
                guard let mode = SVGTransformMode(rawValue: raw) else {
                    throw Failure(
                        code: 2,
                        type: "argument",
                        message: "svg transform must be bake or preserve"
                    )
                }
                svgTransformMode = mode
                svgTransformWasSet = true
            case "--threshold":
                let raw = try value(after: argument)
                if raw == "auto" {
                    threshold = .automatic
                } else if let number = Int(raw), (0...255).contains(number) {
                    threshold = .fixed(UInt8(number))
                } else {
                    throw Failure(code: 2, type: "argument", message: "threshold must be auto or 0...255")
                }
            case "--invert": invert = true
            case "--accuracy": accuracy = try double(try value(after: argument), option: argument)
            case "--smoothing": smoothing = try double(try value(after: argument), option: argument)
            case "--corner-threshold":
                cornerThreshold = try double(try value(after: argument), option: argument)
            case "--min-contour-area":
                minimumContourArea = try double(try value(after: argument), option: argument)
            case "--grid": grid = try integer(try value(after: argument), option: argument)
            case "--structure-grid":
                structureGrid = try integer(try value(after: argument), option: argument)
            case "--refine-raster": refineRaster = true
            case "--no-refine-raster": refineRaster = false
            case "--rtl-start": rtlStart = true
            case "--diagnostics":
                let raw = try value(after: argument)
                guard let level = DiagnosticLevel(rawValue: raw) else {
                    throw Failure(code: 2, type: "argument", message: "diagnostics must be none or summary")
                }
                diagnostics = level
            case "--target-y-min": targetYMin = try double(try value(after: argument), option: argument)
            case "--target-y-max": targetYMax = try double(try value(after: argument), option: argument)
            case "--source-box":
                let raw = try value(after: argument)
                switch raw {
                case "canvas": sourceBox = .canvas
                case "ink": sourceBox = .ink
                default: throw Failure(code: 2, type: "argument", message: "source box must be canvas or ink")
                }
                sourceBoxWasSet = true
            case "--lsb": lsb = try double(try value(after: argument), option: argument)
            case "--rsb": rsb = try double(try value(after: argument), option: argument)
            case "--advance": advance = try double(try value(after: argument), option: argument)
            case "--center-in-advance":
                centeredAdvance = try double(try value(after: argument), option: argument)
            case "--placement-grid":
                placementGrid = try integer(try value(after: argument), option: argument)
            default:
                if argument.hasPrefix("--") {
                    throw Failure(code: 2, type: "argument", message: "unknown option: \(argument)")
                }
                inputs.append(argument)
            }
            index += 1
        }

        switch command {
        case .trace, .inspect:
            guard inputs.count == 1 else {
                let name = command == .trace ? "trace" : "inspect"
                throw Failure(code: 2, type: "argument", message: "\(name) requires exactly one input")
            }
        case .batch:
            guard !inputs.isEmpty else {
                throw Failure(code: 2, type: "argument", message: "batch requires at least one input")
            }
        }
        guard let format else {
            throw Failure(code: 2, type: "argument", message: "--format is required")
        }
        if svgTransformWasSet, format != .svg {
            throw Failure(
                code: 2,
                type: "argument",
                message: "--svg-transform is valid only with --format svg"
            )
        }
        if svgTransformWasSet, command == .inspect {
            throw Failure(code: 2, type: "argument", message: "--svg-transform is not valid with inspect")
        }
        if command == .inspect, format != .json {
            throw Failure(code: 2, type: "argument", message: "inspect format must be json")
        }
        if command == .batch {
            guard output == nil else {
                throw Failure(code: 2, type: "argument", message: "batch uses --output-dir, not --output")
            }
            guard outputDirectory != nil else {
                throw Failure(code: 2, type: "argument", message: "batch requires --output-dir")
            }
        } else if outputDirectory != nil {
            throw Failure(code: 2, type: "argument", message: "--output-dir is valid only for batch")
        }

        let placementRequested = targetYMin != nil || targetYMax != nil || sourceBoxWasSet
            || lsb != nil || rsb != nil || advance != nil || centeredAdvance != nil || placementGrid != nil
        let placement: PlacementOptions?
        if placementRequested {
            guard let targetYMin, let targetYMax else {
                throw Failure(code: 2, type: "argument", message: "placement requires --target-y-min and --target-y-max")
            }
            let mode: HorizontalMetricsMode
            if let centeredAdvance {
                guard lsb == nil, rsb == nil, advance == nil else {
                    throw Failure(code: 2, type: "argument", message: "select exactly one horizontal placement mode")
                }
                mode = .centered(advance: centeredAdvance)
            } else if let advance {
                guard let lsb, rsb == nil else {
                    throw Failure(code: 2, type: "argument", message: "--advance requires --lsb and excludes --rsb")
                }
                mode = .advance(width: advance, left: lsb)
            } else {
                guard let lsb, let rsb else {
                    throw Failure(code: 2, type: "argument", message: "placement requires a horizontal metrics mode")
                }
                mode = .sidebearings(left: lsb, right: rsb)
            }
            placement = PlacementOptions(
                sourceBox: sourceBox,
                targetYMin: targetYMin,
                targetYMax: targetYMax,
                horizontalMode: mode,
                grid: placementGrid ?? grid
            )
        } else {
            placement = nil
        }

        return ParsedCommand(
            command: command,
            inputs: inputs,
            format: format,
            output: output,
            outputDirectory: outputDirectory,
            svgTransformMode: svgTransformMode,
            options: TraceOptions(
                threshold: threshold,
                invert: invert,
                minimumContourArea: minimumContourArea,
                accuracy: accuracy,
                smoothing: smoothing,
                cornerThresholdDegrees: cornerThreshold,
                grid: grid,
                structureGrid: structureGrid,
                refineRaster: refineRaster,
                rtlStart: rtlStart,
                diagnostics: diagnostics
            ),
            placement: placement
        )
    }

    private static func failure(for error: TraceError) -> Failure {
        let code: Int32
        let type: String
        switch error {
        case .invalidOptions, .invalidPlacement:
            code = 2; type = "argument"
        case .emptyInput, .encodedInputTooLarge, .malformedImage,
             .unsupportedImageFormat, .decodedImageTooLarge:
            code = 3; type = "input"
        case .noContours:
            code = 4; type = "noContours"
        case .invalidGeometry:
            code = 5; type = "tracing"
        case .serialization:
            code = 6; type = "output"
        case .internalInvariant:
            code = 7; type = "internal"
        }
        return Failure(code: code, type: type, message: error.localizedDescription)
    }

    private static func failed(_ failure: Failure, json: Bool) -> CLIRunResult {
        let error: Data
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let envelope = ErrorEnvelope(
                exitCode: failure.code,
                error: .init(type: failure.type, message: failure.message)
            )
            var encoded = (try? encoder.encode(envelope)) ?? Data()
            encoded.append(0x0A)
            error = encoded
        } else {
            error = Data("beztrace: \(failure.message)\n".utf8)
        }
        return CLIRunResult(exitCode: failure.code, standardOutput: Data(), standardError: error)
    }

    private static func success(output: Data = Data()) -> CLIRunResult {
        CLIRunResult(exitCode: 0, standardOutput: output, standardError: Data())
    }

    private static let help = """
    Usage:
      beztrace trace INPUT --format json|svg [--svg-transform bake|preserve] [--output PATH] [options]
      beztrace batch INPUT... --format json|svg [--svg-transform bake|preserve] --output-dir DIRECTORY [options]
      beztrace inspect INPUT --format json [options]
      beztrace --version

    """
}
