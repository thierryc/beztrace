// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Original matcher, informed by the pinned img2bez joint/compatibility concepts.
// No Rust dependency code or newer img2bez behavior is translated.

import CryptoKit
import Foundation

public enum OutlineMatcher {
    public static func match(_ request: MasterMatchRequest) throws -> MasterMatchResult {
        try validate(request)
        let reference = try request.reference.outline.contours.map(MatchRing.init)
        let target = try request.target.outline.contours.map(MatchRing.init)
        let referenceCount=reference.reduce(0) { $0+$1.spans.count }
        for (role,master,rings) in [("reference",request.reference,reference),("target",request.target,target)] {
            for (ci,ring) in rings.enumerated() {
                try MatchGeometry.validate(ring,unitsPerEm:request.unitsPerEm,
                    context:.init(stage:"input",role:role,masterID:master.id,contour:ci,existedBeforeFitting:true))
            }
        }
        guard reference.count == target.count else { throw MasterMatchError.topology("contour counts differ; no counters will be fabricated") }
        if request.options.preserveStructure { return try review(request) }
        _ = try MatchNodeBudget.check(referenceCount,referenceCount:referenceCount,options:request.options,totalNodes:request.reference.outline.contours.reduce(0) { $0+$1.nodes.count })
        let pairs = try pair(reference, target, overrides: request.options.contourPairs)
        var outputReference: [Contour] = [], outputTarget: [Contour] = [], reports: [MatchContourReport] = []
        let refBounds = reference.dropFirst().reduce(reference[0].bounds) { $0.union($1.bounds) }
        let targetBounds = target.dropFirst().reduce(target[0].bounds) { $0.union($1.bounds) }
        for i in reference.indices {
            let r = reference[i], original = target[pairs[i]]
            let reversed = r.area * original.area < 0
            var t = reversed ? original.reversed() : original
            let override = request.options.startNodes.isEmpty ? -1 : request.options.startNodes[i]
            let offset = try startingPoint(r, t, referenceBounds: refBounds, targetBounds: targetBounds,
                                           override: override, contour: i)
            t = t.rotated(offset)
            let targetStart = t.spans[0].startSource!
            let tolerance = request.options.fitTolerance
            var rr = r
            let tt: MatchRing
            if request.options.referencePolicy == .fixed {
                let map=anchors(r,t), rf=r.fractions(), tf=t.fractions()
                let positioned=r.spans.count == t.spans.count && r.spans.indices.allSatisfy {
                    abs(warp(rf[$0],map)-tf[$0])<=1.0/64
                }
                if positioned && zip(r.spans,t.spans).allSatisfy({ $0.line == $1.line }) {
                    tt = t
                } else { tt = try fit(t, to: r, contour: i, tolerance: tolerance) }
            } else {
                let aligned = try shared(r, t)
                let used=outputReference.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count }
                let remaining=reference.dropFirst(i+1).reduce(0) { $0+$1.spans.count }
                if used+aligned.0.spans.count+remaining <= MatchNodeBudget.limit(request.options,referenceCount:referenceCount) {
                    rr=aligned.0; tt=aligned.1
                } else {
                    // A redundant target knot must not inflate the reference.
                    // Refit only the target, retaining all reference geometry.
                    do {
                        let fitted=try fit(t,to:r,contour:i,tolerance:tolerance,allowElevation:true)
                        guard MatchGeometry.deviation(t,fitted,tolerance:tolerance)<=tolerance else { throw MasterMatchError.fit(i,"bounded target refitting exceeds tolerance") }
                        for k in rr.spans.indices where !rr.spans[k].line || !fitted.spans[k].line { rr.spans[k].line=false }
                        tt=MatchRing(spans:zip(rr.spans,fitted.spans).map { a,b in var span=b; span.line=a.line; return span },prefix:r.prefix)
                    } catch {
                        throw MasterMatchError.nodeBudget("contour \(i) would add \(aligned.0.spans.count-r.spans.count) reference on-curves; economical target refitting failed: \(error)")
                    }
                }
            }
            try MatchGeometry.validate(rr, unitsPerEm: request.unitsPerEm,context:.init(stage:"fitted",role:"reference",masterID:request.reference.id,contour:i,existedBeforeFitting:false))
            try MatchGeometry.validate(tt, unitsPerEm: request.unitsPerEm,context:.init(stage:"fitted",role:"target",masterID:request.target.id,contour:pairs[i],existedBeforeFitting:false))
            let refData: (Contour, [Int?])
            if request.options.referencePolicy == .fixed {
                refData = (request.reference.outline.contours[i], request.reference.outline.contours[i].nodes.indices.map { Optional($0) })
            } else { refData = rr.serialized(prefix: r.prefix) }
            let targetData = tt.serialized(prefix: r.prefix)
            guard refData.0.nodes.map(\.type) == targetData.0.nodes.map(\.type) else {
                throw MasterMatchError.fit(i, "reference segment types cannot represent the target")
            }
            let deviation = request.options.referencePolicy == .sharedSubdivision ? 0 : MatchGeometry.deviation(original, tt, tolerance: tolerance)
            guard deviation <= tolerance else { throw MasterMatchError.fit(i, "target deviation \(deviation) exceeds tolerance \(tolerance)") }
            outputReference.append(refData.0); outputTarget.append(targetData.0)
            reports.append(MatchContourReport(referenceContour: i, targetContour: pairs[i], targetStartNode: targetStart,
                targetReversed: reversed, insertedReferenceNodes: max(0, rr.spans.count - r.spans.count),
                insertedTargetNodes: max(0, tt.spans.count - original.spans.count), maximumTargetDeviation: deviation,
                referenceSourceNodes: refData.1, targetSourceNodes: targetData.1,
                nodeIDs: refData.0.nodes.indices.map { "c\(i).n\($0)" }))
        }
        let a = Outline(contours: outputReference), b = Outline(contours: outputTarget)
        let interpolation = try InterpolationValidator.validate(reference: a, target: b, unitsPerEm: request.unitsPerEm)
        let invalid = interpolation.issues.filter { $0.message != "smooth join tangency residual" }
        if let issue = invalid.first {
            if let diagnostic = issue.diagnostic { throw MasterMatchError.geometryDiagnostic(diagnostic) }
            throw MasterMatchError.geometry("linear interpolation fails at \(issue.factor): \(issue.message)")
        }
        var result = MasterMatchResult(unitsPerEm: request.unitsPerEm, axis: request.axis,
            reference: .init(id: request.reference.id, outline: a), target: .init(id: request.target.id, outline: b),
            options: request.options, sourceHashes: try [hash(request.reference.outline), hash(request.target.outline)],
            sourceMasters: [request.reference, request.target],
            contours: reports, interpolation: interpolation,
            warnings: interpolation.issues.isEmpty ? [] : ["Linear interpolation has sampled tangency residuals; native HOI review is required."])
        result.nodeBudget=try MatchNodeBudget.check(outputReference.reduce(0) { $0+$1.nodes.filter { $0.type != .offcurve }.count },referenceCount:referenceCount,options:request.options,totalNodes:outputReference.reduce(0) { $0+$1.nodes.count })
        return result
    }

    private static func review(_ request: MasterMatchRequest) throws -> MasterMatchResult {
        guard request.options.contourPairs.isEmpty, request.options.startNodes.isEmpty else {
            throw MasterMatchError.invalid("structure-preserving review does not accept correspondence overrides")
        }
        let a = request.reference.outline, b = request.target.outline
        guard zip(a.contours,b.contours).allSatisfy({ $0.nodes.map(\.type) == $1.nodes.map(\.type) }) else {
            throw MasterMatchError.topology("review requires compatible node structures")
        }
        let report = try InterpolationValidator.validate(reference:a,target:b,unitsPerEm:request.unitsPerEm)
        if let issue = report.issues.first(where: { $0.message != "smooth join tangency residual" }) {
            if let diagnostic = issue.diagnostic { throw MasterMatchError.geometryDiagnostic(diagnostic) }
            throw MasterMatchError.geometry("review interpolation fails at \(issue.factor): \(issue.message)")
        }
        let contours = a.contours.indices.map { i in MatchContourReport(referenceContour:i,targetContour:i,
            targetStartNode:b.contours[i].nodes.firstIndex { $0.type != .offcurve }!,targetReversed:false,
            insertedReferenceNodes:0,insertedTargetNodes:0,maximumTargetDeviation:0,
            referenceSourceNodes:a.contours[i].nodes.indices.map { Optional($0) },
            targetSourceNodes:b.contours[i].nodes.indices.map { Optional($0) },
            nodeIDs:a.contours[i].nodes.indices.map { "c\(i).n\($0)" }) }
        return MasterMatchResult(unitsPerEm:request.unitsPerEm,axis:request.axis,reference:request.reference,target:request.target,
            options:request.options,sourceHashes:try [hash(a),hash(b)],sourceMasters:[request.reference,request.target],
            contours:contours,interpolation:report,warnings:report.issues.isEmpty ? [] : ["Sampled smooth joins require native HOI review."])
    }

    static func validate(_ r: MasterMatchRequest) throws {
        try MatchNodeBudget.validate(r.options)
        guard r.schemaVersion == 1, r.unitsPerEm.isFinite, (16...16384).contains(r.unitsPerEm),
              !r.axis.tag.isEmpty, r.axis.tag.utf8.count <= 64, r.axis.locations.count == 2,
              r.axis.locations.allSatisfy(\.isFinite), r.axis.locations[0] != r.axis.locations[1],
              !r.reference.id.isEmpty, !r.target.id.isEmpty, r.reference.id != r.target.id,
              r.reference.id.utf8.count <= 255, r.target.id.utf8.count <= 255,
              r.options.fitTolerance.isFinite, r.options.fitTolerance > 0, r.options.fitTolerance <= r.unitsPerEm / 10,
              !r.reference.outline.contours.isEmpty, !r.target.outline.contours.isEmpty,
              max(r.reference.outline.contours.count, r.target.outline.contours.count) <= 64,
              (r.reference.outline.contours + r.target.outline.contours).reduce(0, { $0 + $1.nodes.count }) <= 8192,
              r.options.startNodes.isEmpty || r.options.startNodes.count == r.reference.outline.contours.count else {
            throw MasterMatchError.invalid("version, UPM, axis, masters, options or resource limits")
        }
    }
    static func hash(_ outline: Outline) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(outline)).map { String(format: "%02x", $0) }.joined()
    }

    static func pair(_ a: [MatchRing], _ b: [MatchRing], overrides: [Int]) throws -> [Int] {
        let n = a.count, da = MatchGeometry.depths(a), db = MatchGeometry.depths(b)
        guard da.sorted() == db.sorted() else { throw MasterMatchError.topology("contour nesting differs") }
        if !overrides.isEmpty {
            guard overrides.count == n, Set(overrides) == Set(0..<n), a.indices.allSatisfy({ da[$0] == db[overrides[$0]] }) else {
                throw MasterMatchError.invalid("contourPairs must be a nesting-preserving permutation")
            }
            return overrides
        }
        if n == 1 { return [0] }
        let ba = a.dropFirst().reduce(a[0].bounds) { $0.union($1.bounds) }
        let bb = b.dropFirst().reduce(b[0].bounds) { $0.union($1.bounds) }
        let costs = a.indices.map { i in b.indices.map { j in
            guard da[i] == db[j] else { return 1e9 }
            let x = a[i].bounds, y = b[j].bounds
            let center = normalized(Point2D(x: (x.minX + x.maxX) / 2, y: (x.minY + x.maxY) / 2), ba)
            let other = normalized(Point2D(x: (y.minX + y.maxX) / 2, y: (y.minY + y.maxY) / 2), bb)
            let extent = abs(x.width / max(ba.width, 1) - y.width / max(bb.width, 1))
                + abs(x.height / max(ba.height, 1) - y.height / max(bb.height, 1))
            return center.matchDistance(to: other) + extent + abs(log(max(abs(a[i].area), 1e-9) / max(abs(b[j].area), 1e-9))) * 0.05
        } }
        let best = assignment(costs)
        for i in a.indices {
            var other = costs; other[i][best.0[i]] = 1e9
            if assignment(other).1 <= best.1 + 1e-8 { throw MasterMatchError.ambiguousContour(i) }
        }
        return best.0
    }

    // Minimum-cost bipartite assignment, implemented from the mathematical
    // primal/dual augmenting-path method; bounded by the 64-contour limit.
    static func assignment(_ costs: [[Double]]) -> ([Int], Double) {
        let n = costs.count
        var u = Array(repeating: 0.0, count: n + 1), v = u
        var p = Array(repeating: 0, count: n + 1), way = p
        for i in 1...n {
            p[0] = i; var j0 = 0
            var minv = Array(repeating: Double.infinity, count: n + 1), used = Array(repeating: false, count: n + 1)
            repeat {
                used[j0] = true; let i0 = p[j0]
                var delta = Double.infinity, j1 = 0
                for j in 1...n where !used[j] {
                    let cur = costs[i0 - 1][j - 1] - u[i0] - v[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...n {
                    if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat { let j1 = way[j0]; p[j0] = p[j1]; j0 = j1 } while j0 != 0
        }
        var result = Array(repeating: 0, count: n)
        for j in 1...n { result[p[j] - 1] = j - 1 }
        return (result, result.indices.reduce(0) { $0 + costs[$1][result[$1]] })
    }

    static func normalized(_ p: Point2D, _ b: Bounds) -> Point2D {
        Point2D(x: (p.x - b.minX) / max(b.width, 1), y: (p.y - b.minY) / max(b.height, 1))
    }
    static func corner(_ ring: MatchRing, _ i: Int) -> Bool {
        let before = ring.spans[(i + ring.spans.count - 1) % ring.spans.count].curve.derivative(at: 1)
        let after = ring.spans[i].curve.derivative(at: 0)
        guard let a = before.matchNormalized(), let b = after.matchNormalized() else { return true }
        return abs(atan2(a.cross(b), a.dot(b))) > 0.17
    }
    static func signature(_ ring: MatchRing, _ i: Int) -> Int {
        if let role = ring.spans[i].featureRole { return role }
        if corner(ring, i) {
            let a = ring.spans[(i + ring.spans.count - 1) % ring.spans.count].curve.derivative(at: 1)
            let b = ring.spans[i].curve.derivative(at: 0)
            return a.cross(b) >= 0 ? 1 : -1
        }
        if ring.spans[i].line && ring.spans[(i + ring.spans.count - 1) % ring.spans.count].line { return 0 }
        let d = ring.spans[i].curve.derivative(at: 0).matchNormalized() ?? .zero
        if abs(d.dx) < 0.02 { return d.dy >= 0 ? 2 : -2 }
        if abs(d.dy) < 0.02 { return d.dx >= 0 ? 3 : -3 }
        return 0
    }
    static func startingPoint(_ a: MatchRing, _ b: MatchRing, referenceBounds: Bounds, targetBounds: Bounds,
                              override: Int, contour: Int) throws -> Int {
        if override >= 0 {
            guard let i = b.spans.firstIndex(where: { $0.startSource == override }) else {
                throw MasterMatchError.invalid("startNodes must identify input target on-curves")
            }
            return i
        }
        let sig = signature(a, 0)
        let pa = normalized(a.spans[0].curve.start, referenceBounds)
        let shapeA=MatchCorrespondence.samples(a,count:32)
        let shapeB=MatchCorrespondence.samples(b)
        let fractions=b.fractions()
        var candidates: [(Int, Double)] = []
        for i in b.spans.indices {
            let s = signature(b, i)
            let pb = normalized(b.spans[i].curve.start, targetBounds)
            // An arbitrary source first node need not have the same feature
            // label after rasterization. Compare the entire cyclic shape and
            // tangent sequence, not just this one node or equal node indices.
            let shape=(0..<32).reduce(0.0) { total,k in
                let f=(fractions[i]+Double(k)/32).truncatingRemainder(dividingBy:1)
                let j=Int((f*128).rounded())%128
                return total+MatchCorrespondence.cost(shapeA[k],shapeB[j])/32
            }
            let score=pa.matchDistance(to:pb)*pa.matchDistance(to:pb)+shape*2+(s == sig ? 0 : 0.01)
            candidates.append((i, score))
        }
        candidates.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        if candidates.count > 1 && abs(candidates[0].1 - candidates[1].1) <= 1e-8 { throw MasterMatchError.ambiguousStart(contour) }
        return candidates[0].0
    }

    /// Monotone landmark map. Extra non-landmark knots do not change the map.
    static func anchors(_ a: MatchRing, _ b: MatchRing) -> [(Double, Double)] {
        let geometric = MatchCorrespondence.map(a,b)
        let fa = a.fractions(), fb = b.fractions()
        let ia = a.spans.indices.filter { signature(a, $0) != 0 && $0 != 0 }
        let ib = b.spans.indices.filter { signature(b, $0) != 0 && $0 != 0 }
        let ba = a.bounds, bb = b.bounds
        // Ordered sequence alignment with gaps. Features match only by role.
        var dp = Array(repeating: Array(repeating: 0.0, count: ib.count + 1), count: ia.count + 1)
        var back = Array(repeating: Array(repeating: 0, count: ib.count + 1), count: ia.count + 1)
        for i in 0...ia.count { dp[i][0] = Double(i) * 0.3; back[i][0] = 1 }
        for j in 0...ib.count { dp[0][j] = Double(j) * 0.3; back[0][j] = 2 }
        if !ia.isEmpty && !ib.isEmpty {
            for i in 1...ia.count { for j in 1...ib.count {
                let position = normalized(a.spans[ia[i - 1]].curve.start, ba).matchDistance(to:
                    normalized(b.spans[ib[j - 1]].curve.start, bb))
                let match = signature(a, ia[i - 1]) == signature(b, ib[j - 1])
                    ? dp[i - 1][j - 1] + position + abs(fa[ia[i - 1]] - fb[ib[j - 1]]) * 0.1 : Double.infinity
                let choices = [(match, 0), (dp[i - 1][j] + 0.3, 1), (dp[i][j - 1] + 0.3, 2)]
                let best = choices.min { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }!
                dp[i][j] = best.0; back[i][j] = best.1
            } }
        }
        var i = ia.count, j = ib.count, result: [(Double, Double)] = [(1, 1)]
        while i > 0 || j > 0 {
            switch back[i][j] {
            case 0:
                let r=fa[ia[i-1]], t=fb[ib[j-1]]
                // Keep exact landmarks only when shape alignment agrees. An
                // unrelated corner must not drag an entire bowl or terminal.
                if abs(warp(r,geometric)-t)<MatchCorrespondence.landmarkWindow { result.append((r,t)) }
                i -= 1; j -= 1
            case 1: i -= 1
            default: j -= 1
            }
        }
        result.append((0, 0))
        let landmarks=Array(result.reversed())
        var merged=landmarks
        for (left,right) in zip(landmarks,landmarks.dropFirst()) {
            merged += geometric.filter { $0.0>left.0 && $0.0<right.0 && $0.1>left.1 && $0.1<right.1 }
        }
        return merged.sorted { $0.0<$1.0 }
    }
    static func warp(_ value: Double, _ anchors: [(Double, Double)], inverse: Bool = false) -> Double {
        if anchors.allSatisfy({ $0.0 == $0.1 }) { return value }
        let map = inverse ? anchors.map { ($0.1, $0.0) } : anchors
        for (a, b) in zip(map, map.dropFirst()) where value <= b.0 + 1e-9 {
            return a.1 + (b.1 - a.1) * max(0, min(1, (value - a.0) / max(b.0 - a.0, 1e-12)))
        }
        return 1
    }

    static func shared(_ a: MatchRing, _ b: MatchRing) throws -> (MatchRing, MatchRing) {
        let map = anchors(a, b)
        var fractions = a.fractions() + b.fractions().map { warp($0, map, inverse: true) } + [1]
        fractions.sort()
        var cuts: [Double] = []
        for f in fractions where cuts.last.map({ abs($0 - f) > 1e-7 }) ?? true { cuts.append(f) }
        var aa: [MatchSpan] = [], bb: [MatchSpan] = []
        for (start, end) in zip(cuts, cuts.dropFirst()) {
            // Every original knot appears in the union, so both are exact subspans.
            guard var sa = a.subspan(start, end), var sb = b.subspan(warp(start, map), warp(end, map)) else {
                throw MasterMatchError.geometry("shared subdivision could not preserve an original span")
            }
            if !sa.line || !sb.line { sa.line = false; sb.line = false }
            aa.append(sa); bb.append(sb)
        }
        return (MatchRing(spans: aa, prefix: a.prefix), MatchRing(spans: bb, prefix: a.prefix))
    }

    static func fit(_ target: MatchRing, to reference: MatchRing, contour: Int, tolerance: Double, allowElevation: Bool = false) throws -> MatchRing {
        do { return try fitInitial(target,to:reference,contour:contour,tolerance:tolerance,allowElevation:allowElevation) }
        catch {
            // A chord/least-squares refusal is not a representation proof.
            // Reuse the bounded fixed fitter against the original vector's
            // certified boundary, without rendering or spending more nodes.
            return try MatchingStructureFitter.fitVector(target,to:reference,contour:contour,tolerance:tolerance)
        }
    }

    private static func fitInitial(_ target: MatchRing, to reference: MatchRing, contour: Int, tolerance: Double, allowElevation: Bool) throws -> MatchRing {
        let map = anchors(reference, target)
        let cuts = reference.fractions() + [1], tf = target.fractions()
        var spans: [MatchSpan] = []
        for i in reference.spans.indices {
            let start = warp(cuts[i], map), end = warp(cuts[i + 1], map)
            var span: MatchSpan
            if let exact = target.subspan(start, end) { span = exact }
            else {
                for k in target.spans.indices where tf[k] > start + 1e-7 && tf[k] < end - 1e-7 && corner(target, k) {
                    throw MasterMatchError.fit(contour, "fixed structure would remove an intentional target corner")
                }
                let samples = (0...64).map { target.point(start + (end - start) * Double($0) / 64) }
                let (ai, at) = target.location(start), (bi, bt) = target.location(end)
                let da = target.spans[ai].curve.derivative(at: at).matchNormalized() ?? Vector2D(dx: 1, dy: 0)
                let incoming = bt < 1e-7 && end > 0
                    ? target.spans[(bi + target.spans.count - 1) % target.spans.count].curve.derivative(at: 1)
                    : target.spans[bi].curve.derivative(at: bt)
                let db = -(incoming.matchNormalized() ?? Vector2D(dx: 1, dy: 0))
                let fit = ContourFitter.constrainedCubicFit(samples: samples, startTangent: da, endTangent: db, deterministicLengths: true)
                span = MatchSpan(curve: fit.curve, line: false, startSource: at < 1e-7 ? target.spans[ai].startSource : nil,
                                 controlSources: [nil, nil], smooth: at < 1e-7 ? target.spans[ai].smooth : true)
                if chordDeviation(samples) <= 1e-8 { span.curve = lineCubic(from: samples[0], to: samples.last!); span.line = true }
            }
            if reference.spans[i].line && !allowElevation {
                if !span.line {
                    let line = lineCubic(from: span.curve.start, to: span.curve.end)
                    let samples = (0...64).map { span.curve.point(at: Double($0) / 64) }
                    if samples.map({ MatchGeometry.distance($0, to: [line.start, line.end]) }).max()! > tolerance {
                        throw MasterMatchError.fit(contour, "a reference line cannot represent this curve")
                    }
                    span.curve = line; span.controlSources = [nil, nil]
                }
                span.line = true
            } else if !reference.spans[i].line { span.line = false }
            spans.append(span)
        }
        return MatchRing(spans: spans, prefix: reference.prefix)
    }
}
