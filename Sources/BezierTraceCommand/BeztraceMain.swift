// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Darwin
import Foundation

@main
struct BeztraceMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let result = CLIApplication.run(
            arguments: arguments,
            standardInput: arguments.contains("-")
                ? FileHandle.standardInput.readDataToEndOfFile()
                : Data()
        )
        if !result.standardOutput.isEmpty {
            FileHandle.standardOutput.write(result.standardOutput)
        }
        if !result.standardError.isEmpty {
            FileHandle.standardError.write(result.standardError)
        }
        Darwin.exit(result.exitCode)
    }
}
