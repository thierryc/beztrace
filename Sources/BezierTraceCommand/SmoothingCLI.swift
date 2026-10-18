// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import BezierTraceCore

enum SmoothingCLI {
    static func execute(_ args: [String],standardInput: Data) throws -> CLIRunResult {
        var input:String?,output:String?,index=1
        while index<args.count {
            if args[index]=="--json-errors" { index+=1;continue }
            if args[index]=="--output",output==nil,index+1<args.count { output=args[index+1];index+=2;continue }
            guard input==nil,args[index]=="-" || !args[index].hasPrefix("-") else {
                throw MasterMatchError.invalid("smooth-masters requires REQUEST.json|- [--output RESULT.json]")
            }
            input=args[index];index+=1
        }
        guard let input else { throw MasterMatchError.invalid("smooth-masters requires a request") }
        let data=input=="-" ? standardInput : try PairCLI.read(URL(fileURLWithPath:input))
        guard !data.isEmpty,data.count<=16*1024*1024 else { throw MasterMatchError.invalid("smoothing request must contain 1 byte...16MiB") }
        let request:JointSmoothingRequest
        do {
            let raw=try JSONSerialization.jsonObject(with:data)
            let dictionary=try PairCLI.keys(raw,["schemaVersion","unitsPerEm","fitTolerance","reference","target","sourceTarget"],"smoothing")
            for key in ["reference","target","sourceTarget"] { try PairCLI.validateOutline(dictionary[key] as Any) }
            request=try JSONDecoder().decode(JointSmoothingRequest.self,from:data)
        } catch { throw MasterMatchError.invalid("smoothing request: \(error)") }
        let result=try JointMasterSmoother.smooth(request)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        let encoded=try encoder.encode(result)+Data([10])
        if let output { try encoded.write(to:URL(fileURLWithPath:output),options:.atomic) }
        return .init(exitCode:result.report.status == .refused ? 5 : 0,
                     standardOutput:output==nil ? encoded : Data(),standardError:Data())
    }
}
