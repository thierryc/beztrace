// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation
import BezierTraceCore
import CryptoKit

struct PairInputFileError: Error { var message: String }
struct PairFileInput: Codable { var id: String; var kind: String; var path: String; var transform: [Double]? }
struct PairJob: Codable {
    var schemaVersion: Int
    var unitsPerEm: Double
    var axis: MatchAxis
    var inputs: [PairFileInput]
    var strategy: PairStrategy?
    var options: PairMatchConfiguration?
    var rasterOptions: RasterMatchOptions?
    var renderHeight: Int?
}
enum PairCLI {
    static func execute(_ args: [String]) throws -> CLIRunResult {
        var path: String?,out: String?,i=1
        while i<args.count {
            if args[i]=="--json-errors" { i+=1;continue }
            if args[i]=="--output-directory",out==nil,i+1<args.count { out=args[i+1];i+=2;continue }
            guard path==nil,!args[i].hasPrefix("-") else { throw MasterMatchError.invalid("match-pair requires JOB.json --output-directory NEW_DIRECTORY") }
            path=args[i];i+=1
        }
        guard let path,let out else { throw MasterMatchError.invalid("match-pair requires JOB.json --output-directory NEW_DIRECTORY") }
        let url=URL(fileURLWithPath:path),directory=URL(fileURLWithPath:out,isDirectory:true)
        guard !FileManager.default.fileExists(atPath:directory.path) else { throw MasterMatchError.invalid("output-directory already exists; choose a new directory (nothing overwritten)") }
        let data=try read(url)
        let object: Any
        do { object=try JSONSerialization.jsonObject(with:data) }
        catch { throw MasterMatchError.invalid("job must be valid JSON: \(error)") }
        try validate(object)
        let job: PairJob
        do { job=try JSONDecoder().decode(PairJob.self,from:data) }
        catch { throw MasterMatchError.invalid("job field decoding: \(error)") }
        guard job.schemaVersion==1,job.inputs.count==2 else { throw MasterMatchError.invalid("schemaVersion must be 1 and inputs must contain exactly two masters") }
        var files: [[String:String]]=[]
        var sourceBytes: [Data]=[]
        let inputs: [PairInput]=try job.inputs.map { input in
            let f=URL(fileURLWithPath:input.path,relativeTo:url.deletingLastPathComponent()).standardizedFileURL
            let d=try read(f);sourceBytes.append(d)
            files.append(["id":input.id,"kind":input.kind,"sha256":SHA256.hash(data:d).map { String(format:"%02x",$0) }.joined()])
            if input.kind=="outline" {
                guard input.transform==nil else { throw MasterMatchError.invalid("inputs.transform is image-only; outline coordinates already use font units") }
                do {
                    let raw=try JSONSerialization.jsonObject(with:d);try validateOutline(raw)
                    return .outline(.init(id:input.id,outline:try JSONDecoder().decode(Outline.self,from:d)))
                } catch { throw PairInputFileError(message:"inputs.path \(input.path): invalid neutral outline: \(error)") }
            }
            guard input.kind=="image",let m=input.transform else { throw MasterMatchError.invalid("inputs.kind must be outline or image; images require an explicit six-value transform") }
            return .image(.init(id:input.id,imageData:d,transform:m))
        }
        let options=try (job.options ?? .init()).resolved(reference:inputs[0],unitsPerEm:job.unitsPerEm)
        let output=try PairMatcher.match(reference:inputs[0],target:inputs[1],unitsPerEm:job.unitsPerEm,axis:job.axis,options:options,strategy:job.strategy ?? .direct,rasterOptions:job.rasterOptions ?? .init(),renderHeight:job.renderHeight ?? 2048)
        let stage=directory.deletingLastPathComponent().appendingPathComponent(".beztrace-pair-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:stage) }
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys,.prettyPrinted]
        var report=try JSONSerialization.jsonObject(with:enc.encode(output.report)) as! [String:Any]
        report["inputFiles"]=files
        try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:stage.appendingPathComponent("comparison.json"))
        try data.write(to:stage.appendingPathComponent("job.json"))
        for (index,input) in job.inputs.enumerated() {
            try sourceBytes[index].write(to:stage.appendingPathComponent(index==0 ? "input-reference."+input.kind : "input-target."+input.kind))
        }
        for route in output.results.keys.sorted() {
            let result=output.results[route]!
            try MasterMatchSerializer.json(result,pretty:true).write(to:stage.appendingPathComponent(route+".master-set.json"))
            try preview(result).write(to:stage.appendingPathComponent(route+".proof.svg"),atomically:true,encoding:.utf8)
            if route==output.report.recommendedRoute {
                try MasterMatchSerializer.json(result,pretty:true).write(to:stage.appendingPathComponent("recommended.master-set.json"))
                try enc.encode(result.reference.outline).write(to:stage.appendingPathComponent("reference.outline.json"))
                try enc.encode(result.target.outline).write(to:stage.appendingPathComponent("target.outline.json"))
            }
        }
        for name in output.renders.keys.sorted() { try output.renders[name]!.write(to:stage.appendingPathComponent(name)) }
        try html(output.report).write(to:stage.appendingPathComponent("index.html"),atomically:true,encoding:.utf8)
        try FileManager.default.moveItem(at:stage,to:directory)
        if output.report.recommendedRoute==nil {
            let error: [String:Any]=["schemaVersion":1,"exitCode":5,"error":["type":"matching","message":"No route passed. See comparison.json for structured refusals; no result geometry was written."]]
            return .init(exitCode:5,standardOutput:Data(),standardError:try JSONSerialization.data(withJSONObject:error,options:.sortedKeys)+Data([10]))
        }
        let summary: [String:String]=["outputDirectory":directory.path,"recommendedRoute":output.report.recommendedRoute!]
        return .init(exitCode:0,standardOutput:try JSONSerialization.data(withJSONObject:summary,options:.sortedKeys)+Data([10]),standardError:Data())
    }
    static func read(_ url: URL) throws -> Data {
        do {
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size>0,size<=16*1024*1024 else { throw PairInputFileError(message:"input files must contain 1 byte...16MiB") }
            let data=try Data(contentsOf:url)
            guard !data.isEmpty,data.count<=16*1024*1024 else { throw PairInputFileError(message:"input file changed beyond the 16MiB limit") }
            return data
        } catch let error as PairInputFileError { throw error }
        catch { throw PairInputFileError(message:"Cannot read input \(url.lastPathComponent): \(error)") }
    }
    static func keys(_ raw: Any,_ allowed: Set<String>,_ field: String) throws -> [String:Any] {
        guard let d=raw as? [String:Any] else { throw MasterMatchError.invalid("\(field) must be an object") }
        guard let unknown=d.keys.sorted().first(where: { !allowed.contains($0) }) else { return d }
        let name=field+"."+unknown
        let message=name=="options.preserveStructure"
            ? "options.preserveStructure is for reviewing existing vector correspondence with match. Use referencePolicy=fixed to keep the reference exact in match-pair."
            : "Unknown field \(name). See pair-job-v1.schema.json for supported configuration."
        throw MasterMatchError.invalidOption(field:name,message:message)
    }
    static func validate(_ raw: Any) throws {
        let d=try keys(raw,["schemaVersion","unitsPerEm","axis","inputs","strategy","options","rasterOptions","renderHeight"],"job")
        _=try keys(d["axis"] as Any,["tag","locations"],"axis")
        guard let inputs=d["inputs"] as? [Any],inputs.count==2 else { throw MasterMatchError.invalid("inputs must contain exactly two entries") }
        for (i,v) in inputs.enumerated() { _=try keys(v,["id","kind","path","transform"],"inputs[\(i)]") }
        if let o=d["options"] { _=try keys(o,["referencePolicy","fitTolerance","maxAdditionalOnCurveNodes","maxOnCurveNodes","maxNodes","contourPairs","startNodes","smoothJoins"],"options") }
        if let o=d["rasterOptions"] { _=try keys(o,["threshold","invert","minimumContourArea","smoothing","cornerThresholdDegrees"],"rasterOptions") }
    }
    static func validateOutline(_ raw: Any) throws {
        let o=try keys(raw,["contours"],"outline")
        guard let contours=o["contours"] as? [Any],!contours.isEmpty,contours.count<=64 else { throw MasterMatchError.invalid("outline.contours must contain 1...64 contours") }
        for c in contours {
            let d=try keys(c,["closed","nodes"],"contour")
            guard let nodes=d["nodes"] as? [Any],nodes.count<=4096 else { throw MasterMatchError.invalid("contour.nodes resource limit") }
            for n in nodes { _=try keys(n,["x","y","type","smooth"],"node") }
        }
    }
    static func path(_ o: Outline) -> String {
        o.contours.map { c in
            let n=c.nodes,ons=n.indices.filter { n[$0].type != .offcurve }
            var s="M \(n[ons[0]].x) \(-n[ons[0]].y)"
            for k in ons.indices {
                let i=ons[k],j=ons[(k+1)%ons.count];var controls: [Int]=[],z=(i+1)%n.count
                while z != j { controls.append(z);z=(z+1)%n.count }
                if controls.isEmpty { s+=" L \(n[j].x) \(-n[j].y)" }
                else { s+=" C "+controls.map { "\(n[$0].x) \(-n[$0].y)" }.joined(separator:" ")+" \(n[j].x) \(-n[j].y)" }
            };return s+" Z"
        }.joined(separator:" ")
    }
    static func preview(_ r: MasterMatchResult) throws -> String {
        let nodes=(r.reference.outline.contours+r.target.outline.contours).flatMap(\.nodes)
        let minX=nodes.map(\.x).min()!-40,maxX=nodes.map(\.x).max()!+40,minY=nodes.map(\.y).min()!-40,maxY=nodes.map(\.y).max()!+80
        let w=maxX-minX,h=maxY-minY
        var s="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(minX) \(-maxY) \(w*5) \(h*2)\" width=\"1200\" font-family=\"Arial,sans-serif\"><rect x=\"\(minX)\" y=\"\(-maxY)\" width=\"\(w*5)\" height=\"\(h*2)\" fill=\"white\"/>"
        for (i,f) in [0.0,0.25,0.5,0.75,1.0].enumerated() {
            let o=try InterpolationValidator.interpolate(reference:r.reference.outline,target:r.target.outline,factor:f)
            s+="<g transform=\"translate(\(Double(i)*w),0)\"><text x=\"\(minX+10)\" y=\"\(-maxY+30)\" font-size=\"22\">\(Int(f*100))%</text><path d=\"\(path(o))\" fill=\"#17272d\" fill-rule=\"nonzero\"/></g>"
        }
        for (i,o) in [r.reference.outline,r.target.outline].enumerated() {
            s+="<g transform=\"translate(\(Double(i)*w),\(h))\"><path d=\"\(path(o))\" fill=\"none\" stroke=\"#176da2\" stroke-width=\"1\"/>"
            for (ci,c) in o.contours.enumerated() { for (ni,n) in c.nodes.enumerated() { s+="<circle cx=\"\(n.x)\" cy=\"\(-n.y)\" r=\"\(n.type == .offcurve ? 2 : 3)\" fill=\"\(n.type == .offcurve ? "white" : "#176da2")\" stroke=\"#176da2\"/><text x=\"\(n.x+4)\" y=\"\(-n.y-4)\" font-size=\"10\">\(ci):\(ni)</text>" } };s+="</g>"
        };return s+"</svg>"
    }
    static func escaped(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
    static func html(_ report: PairComparisonReport) -> String {
        var s="<!doctype html><html><meta charset=\"utf-8\"><title>BezTrace pair review</title><style>body{font:16px/1.5 system-ui;max-width:1200px;margin:30px auto;padding:20px}img{width:100%}section{border:1px solid #ccc;padding:20px;margin:20px 0}pre{white-space:pre-wrap}</style><h1>BezTrace pair review</h1><p>Detached geometry · no native application or HOI verification</p><p>Recommended route: <strong>\(escaped(report.recommendedRoute ?? "none"))</strong></p><ul>"
        for reason in report.reasons { s+="<li>\(escaped(reason))</li>" };s+="</ul><p><a href=\"comparison.json\">Measurements, provenance and structured refusals</a></p>"
        for c in report.candidates {
            s+="<section><h2>\(c.route): \(c.accepted ? "accepted" : "refused")</h2>"
            if c.accepted { s+="<p>\(c.onCurveNodes!) on-curves / \(c.totalNodes!) nodes. Original source bounds: \(c.sourceDeviations.map { String(format:"%.6fu",$0.upperBound) }.joined(separator:", ")).</p><p><a href=\"\(c.route).master-set.json\">Compatible paths</a></p><img src=\"\(c.route).proof.svg\" alt=\"Five interpolation positions and numbered endpoint nodes\">" }
            else { s+="<p>\(escaped(c.refusal ?? "Unknown refusal"))</p>" };s+="</section>"
        };return s+"</html>"
    }
}
