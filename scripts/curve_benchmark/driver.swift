// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Compiled with local core sources for maintenance-only internal observations.
import Foundation

struct BenchJob: Codable { var id: String; var curves: [[Double]]; var line: Bool }
struct BenchInput: Codable { var jobs: [BenchJob]; var tolerances: [Double]; var repeats: Int }
struct BenchCandidate: Codable {
    var id: String; var tolerance: Double; var method: String
    var curve: [Double]?; var line: Bool; var timesMs: [Double]
    var selectedFitter: String? = nil
}
struct BenchVerification: Codable {
    var id: String; var tolerance: Double; var method: String
    var accepted: Bool; var lower: Double?; var upper: Double?
    var controlled: Bool; var tangentDegrees: Double?; var reason: String?
}
struct BenchOutlineJob: Codable { var id: String; var outlines: [Outline]; var sources: [Outline]; var tolerance: Double }
struct BenchOutlineResult: Codable {
    var id: String; var valid: Bool; var reasons: [String]; var sourceBounds: [Double]
    var maximumTangencyResidual: Double?; var interpolationIssues: Int?
}
struct BenchSmoothingJob: Codable { var id: String; var request: JointSmoothingRequest; var repeats: Int }
struct BenchSmoothingResult: Codable { var id: String; var result: JointSmoothingResult; var timesMs: [Double] }

func unpack(_ c: [Double]) -> CubicBezier {
    .init(start:.init(x:c[0],y:c[1]),control1:.init(x:c[2],y:c[3]),
          control2:.init(x:c[4],y:c[5]),end:.init(x:c[6],y:c[7]))
}
func pack(_ c: CubicBezier) -> [Double] {
    [c.start.x,c.start.y,c.control1.x,c.control1.y,c.control2.x,c.control2.y,c.end.x,c.end.y]
}
func ring(_ curves: [[Double]],line: Bool = false) -> MatchRing {
    .init(spans:curves.map { .init(curve:unpack($0),line:line,startSource:nil,controlSources:[nil,nil],smooth:false) })
}

@main enum CurveBenchmarkDriver {
    static func main() throws {
        let args=CommandLine.arguments
        let data=FileHandle.standardInput.readDataToEndOfFile(),decoder=JSONDecoder()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let output: Data
        switch args[1] {
        case "selftest":
            let line=[Point2D(x:0,y:0),Point2D(x:10,y:0)]
            let shifted=[Point2D(x:0,y:3),Point2D(x:10,y:3)]
            let m=try PairGeometry.measure(line,shifted,tolerance:1,flattenAllowance:0)
            precondition(m.lowerBound<=3 && m.upperBound>=3 && m.upperBound<3.1)
            let peak=try PairGeometry.measure(line,[.init(x:0,y:0),.init(x:5,y:2),.init(x:10,y:0)],tolerance:1,flattenAllowance:0)
            precondition(peak.lowerBound<=2 && peak.upperBound>=2 && peak.lowerBound>1.9)
            let arch=[0.0,0,0,6,10,6,10,0]
            let eps=0.001
            let curved=try PairGeometry.measure(line,PairGeometry.flatten(ring([arch]),epsilon:eps),tolerance:0.1,flattenAllowance:eps)
            precondition(curved.lowerBound<=4.5 && curved.upperBound>=4.5 && curved.lowerBound>4.49)
            output=try encoder.encode(["passed":3])
        case "fit":
            let input=try decoder.decode(BenchInput.self,from:data)
            var results:[BenchCandidate]=[]
            for job in input.jobs where !job.line {
                let curves=job.curves.map(unpack)
                // Identical source span and endpoint directions to the kurbo driver.
                let points=curves.flatMap { c in (0..<33).map { c.point(at:Double($0)/33) } }+[curves.last!.end]
                let first=curves[0].derivative(at:0).matchNormalized()
                let last=curves.last!.derivative(at:1).matchNormalized()
                for tolerance in input.tolerances {
                    for method in ["least-squares-8","least-squares-refined","refined-swift-verified","hybrid-swift"] {
                        var result=curves[0],times:[Double]=[]
                        var hybrid: HybridCubicFitter.Result?
                        var verified=false
                        for iteration in 0..<(input.repeats+2) {
                            let start=DispatchTime.now().uptimeNanoseconds
                            if method=="hybrid-swift" { hybrid=HybridCubicFitter.fit(curves,tolerance:tolerance) }
                            else if method=="refined-swift-verified" {
                                // Equal-workload Swift baseline: source preparation,
                                // sampling, fitting and the same independent checks.
                                let evidence=try SourceGeometryVerifier.prepare(curves,tolerance:tolerance)
                                let sampled=curves.flatMap { c in (0..<33).map { c.point(at:Double($0)/33) } }+[curves.last!.end]
                                result=MatchingCubicFitter.fit(sampled,refinementBudget:tolerance*0.8,startTangent:first,endTangent:last.map { -$0 })
                                verified=(try? SourceGeometryVerifier.verify(result,source:evidence,tolerance:tolerance,
                                    start:curves[0].start,end:curves.last!.end,startTangent:first,endTangent:last).accepted) ?? false
                            }
                            else {
                                result=MatchingCubicFitter.fit(points,refinementBudget:method=="least-squares-8" ? nil : tolerance*0.8,
                                    startTangent:first,endTangent:last.map { -$0 })
                            }
                            let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                            if iteration>=2 { times.append(elapsed) }
                        }
                        results.append(.init(id:job.id,tolerance:tolerance,method:method,
                            curve:method=="hybrid-swift" ? hybrid.map { pack($0.curve) } : (method=="refined-swift-verified" && !verified ? nil : pack(result)),line:false,timesMs:times,
                            selectedFitter:hybrid?.method.rawValue))
                    }
                }
            }
            output=try encoder.encode(results)
        case "verify":
            let input=try decoder.decode(BenchInput.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
            let sources=Dictionary(uniqueKeysWithValues:input.jobs.map { ($0.id,$0) })
            let candidates=try decoder.decode([BenchCandidate].self,from:data)
            var results:[BenchVerification]=[]
            for c in candidates {
                guard let coords=c.curve,coords.count==8,coords.allSatisfy(\.isFinite) else {
                    results.append(.init(id:c.id,tolerance:c.tolerance,method:c.method,accepted:false,controlled:false,reason:"fitter-refusal"));continue
                }
                let source=sources[c.id]!,curve=unpack(coords),original=source.curves.map(unpack)
                let controlled=c.line || MatchGeometry.controlled(curve)
                let start=original[0].derivative(at:0),end=original.last!.derivative(at:1)
                let tangent=max(angleBetween(start,curve.derivative(at:0)),angleBetween(end,curve.derivative(at:1)))*180/Double.pi
                let endpoints=curve.start.matchDistance(to:original[0].start)<1e-7 && curve.end.matchDistance(to:original.last!.end)<1e-7
                do {
                    let eps=c.tolerance/200
                    let m=try PairGeometry.measure(PairGeometry.flatten(ring(source.curves,line:source.line),epsilon:eps),
                        PairGeometry.flatten(ring([coords],line:c.line),epsilon:eps),tolerance:c.tolerance,flattenAllowance:2*eps)
                    let accepted=controlled && endpoints && tangent<0.01 && m.upperBound<=c.tolerance
                    results.append(.init(id:c.id,tolerance:c.tolerance,method:c.method,accepted:accepted,
                        lower:m.lowerBound,upper:m.upperBound,controlled:controlled,tangentDegrees:tangent,
                        reason:accepted ? nil : (!controlled ? "handle-reach" : (!endpoints ? "endpoints" : (tangent>=0.01 ? "tangents" : "source-deviation")))))
                } catch {
                    results.append(.init(id:c.id,tolerance:c.tolerance,method:c.method,accepted:false,controlled:controlled,reason:String(describing:error)))
                }
            }
            output=try encoder.encode(results)
        case "smooth":
            let jobs=try decoder.decode([BenchSmoothingJob].self,from:data)
            var results:[BenchSmoothingResult]=[]
            for job in jobs {
                var result:JointSmoothingResult?,times:[Double]=[]
                for iteration in 0..<(job.repeats+2) {
                    let start=DispatchTime.now().uptimeNanoseconds
                    result=try JointMasterSmoother.smooth(job.request)
                    if iteration>=2 { times.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000) }
                }
                results.append(.init(id:job.id,result:result!,timesMs:times))
            }
            output=try encoder.encode(results)
        case "outlines":
            let jobs=try decoder.decode([BenchOutlineJob].self,from:data)
            var results:[BenchOutlineResult]=[]
            for job in jobs {
                var reasons:[String]=[],bounds:[Double]=[]
                for (i,outline) in job.outlines.enumerated() {
                    do {
                        for (ci,c) in outline.contours.enumerated() { try MatchGeometry.validate(MatchRing(c),unitsPerEm:1000,context:.init(stage:"benchmark",contour:ci)) }
                        let m=try PairGeometry.measure(job.sources[i],outline,tolerance:job.tolerance)
                        bounds.append(m.upperBound)
                        if m.upperBound>job.tolerance { reasons.append("source-deviation master \(i)") }
                        let old=MatchGeometry.depths(try job.sources[i].contours.map(MatchRing.init))
                        let new=MatchGeometry.depths(try outline.contours.map(MatchRing.init))
                        if old != new { reasons.append("nesting master \(i)") }
                    } catch { reasons.append(String(describing:error)) }
                }
                var residual:Double?,issues:Int?
                if job.outlines.count==2 {
                    do {
                        let report=try InterpolationValidator.validate(reference:job.outlines[0],target:job.outlines[1],intervals:200)
                        residual=report.maximumTangencyResidual;issues=report.issues.count
                        if !report.issues.isEmpty { reasons.append("interpolation issues: \(report.issues.count)") }
                    } catch { reasons.append(String(describing:error)) }
                }
                results.append(.init(id:job.id,valid:reasons.isEmpty,reasons:reasons,sourceBounds:bounds,
                    maximumTangencyResidual:residual,interpolationIssues:issues))
            }
            output=try encoder.encode(results)
        case "legacy":
            let jobs=try decoder.decode([BenchOutlineJob].self,from:data)
            var results:[String:[Outline]]=[:]
            for job in jobs {
                results[job.id]=try job.sources.map { outline in
                    Outline(contours:try outline.contours.map { contour in
                        let source=try MatchRing(contour)
                        let simplified=CleanupSimplify.removeRedundantPoints(.init(segments:source.spans.map { .init(cubic:$0.curve,isLine:$0.line) }))
                        return MatchRing(spans:simplified.segments.map { segment in
                            let smooth=source.spans.first(where: { $0.curve.start.matchDistance(to:segment.cubic.start)<1e-9 })?.smooth ?? false
                            return .init(curve:segment.cubic,line:segment.isLine,startSource:nil,controlSources:[nil,nil],smooth:smooth)
                        }).serialized().0
                    })
                }
            }
            output=try encoder.encode(results)
        default: throw NSError(domain:"benchmark",code:2,userInfo:[NSLocalizedDescriptionKey:"Unknown mode"])
        }
        FileHandle.standardOutput.write(output)
    }
}
