// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
// Independently written Double geometry; no dependency implementation translated.

import Foundation

struct MatchSpan {
    var curve: CubicBezier
    var line: Bool
    var startSource: Int?
    var controlSources: [Int?]
    var smooth: Bool
    /// Explicit structural role on a raster planning boundary, nil for vectors.
    var featureRole: Int? = nil
}

struct MatchRing {
    var spans: [MatchSpan]
    var prefix: Int = 0

    init(_ contour: Contour) throws {
        guard contour.closed, !contour.nodes.isEmpty, contour.nodes.count <= 4096,
              contour.nodes.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e9 && abs($0.y) <= 1e9 }),
              let first = contour.nodes.firstIndex(where: { $0.type != .offcurve }) else {
            throw MasterMatchError.geometry("closed finite line/cubic paths are required")
        }
        prefix = first
        spans = []
        var index = first
        var consumed = 0
        repeat {
            let next = (index + 1) % contour.nodes.count
            let end: Int
            let controls: [Int?]
            let curve: CubicBezier
            let line: Bool
            if contour.nodes[next].type == .offcurve {
                let second = (next + 1) % contour.nodes.count
                end = (next + 2) % contour.nodes.count
                guard contour.nodes[second].type == .offcurve, contour.nodes[end].type == .curve,
                      !contour.nodes[next].smooth, !contour.nodes[second].smooth else {
                    throw MasterMatchError.geometry("cubic controls must precede a curve endpoint")
                }
                controls = [next, second]; line = false
                curve = CubicBezier(start: contour.nodes[index].point, control1: contour.nodes[next].point,
                                    control2: contour.nodes[second].point, end: contour.nodes[end].point)
                consumed += 3
            } else {
                end = next
                guard contour.nodes[end].type == .line else { throw MasterMatchError.geometry("curve endpoint has no controls") }
                controls = [nil, nil]; line = true
                curve = lineCubic(from: contour.nodes[index].point, to: contour.nodes[end].point)
                consumed += 1
            }
            spans.append(MatchSpan(curve: curve, line: line, startSource: index,
                                   controlSources: controls, smooth: contour.nodes[index].smooth))
            index = end
        } while index != first && consumed <= contour.nodes.count
        guard consumed == contour.nodes.count, index == first, spans.count >= 3, spans.count <= 1024 else {
            throw MasterMatchError.geometry("invalid closure or segment count (3...1024 required)")
        }
    }

    init(spans: [MatchSpan], prefix: Int = 0) { self.spans = spans; self.prefix = prefix }

    var bounds: Bounds { spans.dropFirst().reduce(spans[0].curve.bounds) { $0.union($1.curve.bounds) } }
    var area: Double {
        let path = BezierPathContour(segments: spans.map { PathSegment(cubic: $0.curve, isLine: $0.line) })
        return CleanupDirection.signedArea(path)
    }

    func rotated(_ offset: Int) -> MatchRing {
        MatchRing(spans: Array(spans[offset...]) + Array(spans[..<offset]), prefix: prefix)
    }

    func reversed() -> MatchRing {
        let n = spans.count
        return MatchRing(spans: (0..<n).map { i in
            let k = (n - i - 1) % n, next = (k + 1) % n
            let s = spans[k], c = s.curve
            return MatchSpan(curve: CubicBezier(start: c.end, control1: c.control2, control2: c.control1, end: c.start),
                             line: s.line, startSource: spans[next].startSource,
                             controlSources: s.controlSources.reversed(), smooth: spans[next].smooth,
                             featureRole: spans[next].featureRole.map { -$0 })
        }, prefix: prefix)
    }

    func serialized(prefix wanted: Int? = nil) -> (Contour, [Int?]) {
        var nodes: [Node] = [], sources: [Int?] = []
        for i in spans.indices {
            let previous = spans[(i + spans.count - 1) % spans.count]
            let s = spans[i]
            nodes.append(Node(x: s.curve.start.x, y: s.curve.start.y, type: previous.line ? .line : .curve, smooth: s.smooth))
            sources.append(s.startSource)
            if !s.line {
                nodes.append(Node(x: s.curve.control1.x, y: s.curve.control1.y, type: .offcurve))
                nodes.append(Node(x: s.curve.control2.x, y: s.curve.control2.y, type: .offcurve))
                sources.append(contentsOf: s.controlSources)
            }
        }
        let count = min(wanted ?? prefix, nodes.count - 1)
        if count > 0 {
            nodes = Array(nodes.suffix(count)) + Array(nodes.dropLast(count))
            sources = Array(sources.suffix(count)) + Array(sources.dropLast(count))
        }
        return (Contour(nodes: nodes), sources)
    }

    func lengths() -> [Double] { spans.map { $0.line ? $0.curve.start.matchDistance(to: $0.curve.end) : MatchGeometry.length($0.curve) } }
    func fractions() -> [Double] {
        let lens = lengths(), total = lens.reduce(0, +)
        var d = 0.0
        return lens.map { length in defer { d += length }; return d / total }
    }
    func location(_ fraction: Double) -> (Int, Double) {
        let lens = lengths(), total = lens.reduce(0, +)
        if fraction >= 1 { return (spans.count-1,1) }
        var remaining = max(0, min(1, fraction)) * total
        for i in spans.indices {
            if remaining < lens[i] - 1e-8 || i == spans.count - 1 {
                // Exact source knots must remain exact even when their endpoint
                // derivative vanishes. Arc-length inversion is ill-conditioned
                // there and can otherwise invent a tiny split across the knot.
                if remaining <= 1e-8 { return (i,0) }
                if spans[i].line { return (i, min(1, max(0, remaining / lens[i]))) }
                var lo = 0.0, hi = 1.0
                for _ in 0..<32 {
                    let mid = (lo + hi) / 2
                    if MatchGeometry.length(spans[i].curve.split(at: mid).0) < remaining { lo = mid } else { hi = mid }
                }
                return (i, (lo + hi) / 2)
            }
            remaining = max(0, remaining - lens[i])
        }
        return (spans.count - 1, 1)
    }
    func point(_ fraction: Double) -> Point2D {
        let (i, t) = location(fraction); return spans[i].curve.point(at: t)
    }
    func subspan(_ start: Double, _ end: Double) -> MatchSpan? {
        let (a, ta) = location(start), (b, tb) = location(end)
        let same = a == b || (b == a + 1 && tb < 1e-7)
        guard same else { return nil }
        let upper = a == b ? tb : 1
        var s = spans[a]
        s.curve = s.curve.split(at: upper).0.split(at: ta / max(upper, 1e-12)).1
        if ta > 1e-7 { s.startSource = nil; s.smooth = true }
        if ta > 1e-7 || upper < 1 - 1e-7 { s.controlSources = [nil, nil] }
        return s
    }

    /// Exact original cubic pieces for a non-wrapping arc-length interval.
    /// Final fitting verifies against these, never against an earlier fit.
    func sourceCurves(_ start: Double,_ end: Double) -> [CubicBezier] {
        guard start>=0,end<=1,start<end else { return [] }
        let (a,ta)=location(start),(b,tb)=location(end)
        var result:[CubicBezier]=[]
        for i in a...b {
            let lo=i==a ? ta : 0,hi=i==b ? tb : 1
            if hi>lo {
                var curve=spans[i].curve
                if hi<1 { curve=curve.split(at:hi).0 }
                if lo>0 { curve=curve.split(at:lo/hi).1 }
                result.append(curve)
            }
        }
        return result
    }
}

enum MatchGeometry {
    struct DiagnosticEdge {
        var start: Point2D
        var end: Point2D
        var location: MatchDiagnosticLocation
    }

    /// Same flattening decisions as validation, retaining original segment/node IDs.
    static func diagnosticEdges(_ ring: MatchRing, tolerance: Double, contour: Int) -> [DiagnosticEdge] {
        var result: [DiagnosticEdge] = []
        for (i, span) in ring.spans.enumerated() {
            func append(_ c: CubicBezier, _ lo: Double, _ hi: Double, _ depth: Int) {
                let d = c.end-c.start
                let reach = max(abs((c.control1-c.start).cross(d)), abs((c.control2-c.start).cross(d))) / max(d.matchMagnitude, 1e-12)
                let polygon = c.start.matchDistance(to:c.control1)+c.control1.matchDistance(to:c.control2)+c.control2.matchDistance(to:c.end)
                if span.line || depth == 12 || (reach <= tolerance && polygon <= d.matchMagnitude+tolerance*2) {
                    result.append(.init(start:c.start,end:c.end,location:.init(contour:contour,segment:i,
                        startNode:span.startSource,endNode:ring.spans[(i+1)%ring.spans.count].startSource,
                        parameterRange:[lo,hi])))
                } else {
                    let (a,b) = c.split(at:0.5), mid = (lo+hi)/2
                    append(a,lo,mid,depth+1); append(b,mid,hi,depth+1)
                }
            }
            append(span.curve,0,1,0)
        }
        return result
    }

    /// Advisory contact evidence; never used by validate or the fitter.
    static func contact(_ a: DiagnosticEdge, _ b: DiagnosticEdge, epsilon: Double) -> (String, Point2D)? {
        let d = a.end-a.start, e = b.end-b.start, denominator = d.cross(e)
        if abs(denominator) > 1e-12 {
            let t = (b.start-a.start).cross(e)/denominator
            let u = (b.start-a.start).cross(d)/denominator
            if (0...1).contains(t), (0...1).contains(u) {
                let endpoint = t == 0 || t == 1 || u == 0 || u == 1
                return (endpoint ? "endpoint-contact" : "crossing", a.start+d*t)
            }
        } else if abs((b.start-a.start).cross(d)) <= 1e-12, d.dot(d) > 1e-24 {
            let x = (b.start-a.start).dot(d)/d.dot(d), y = (b.end-a.start).dot(d)/d.dot(d)
            let lo = max(0,min(x,y)), hi = min(1,max(x,y))
            if lo <= hi { return (lo == hi ? "endpoint-contact" : "overlap",a.start+d*((lo+hi)/2)) }
        }
        for (point,other) in [(a.start,b),(a.end,b),(b.start,a),(b.end,a)] {
            if distance(point,to:[other.start,other.end]) <= epsilon { return ("near-coincidence",point) }
        }
        return nil
    }
    static func controlled(_ curve: CubicBezier) -> Bool {
        guard curve.isFinite else { return false }
        let tolerance = HandleSafety.validationTolerance
        if HandleSafety.isControlled(curve,tolerance:tolerance) { return true }
        // The tracing fitter's tangent-triangle rule is a conservative fitting
        // heuristic. Its ray intersection can switch sides after font storage
        // rounding, rejecting an otherwise regular, short monotone cubic.
        // Accept that case only with a separate geometric certificate: all
        // three derivative control vectors project forward on the chord, and
        // handle reach still obeys the original bound. Their Bernstein blend
        // then projects forward too, so the curve cannot fold or self-intersect.
        let chord = curve.end-curve.start, length = chord.matchMagnitude
        guard curve.isFinite, length>1e-9 else { return false }
        let direction = chord/length
        let first = curve.control1-curve.start, last = curve.end-curve.control2
        let reach = (first+last).dot(direction)
        guard reach <= length*HandleSafety.maximumReachRatio+tolerance else { return false }
        return [first,curve.control2-curve.control1,last].allSatisfy { $0.dot(direction)>=0 }
    }
    static func length(_ c: CubicBezier) -> Double {
        // Composite Gauss-Legendre integration of the exact cubic derivative.
        let x = [-0.906179845938664, -0.538469310105683, 0, 0.538469310105683, 0.906179845938664]
        let w = [0.236926885056189, 0.478628670499366, 0.568888888888889, 0.478628670499366, 0.236926885056189]
        return (0..<4).reduce(0) { sum, part in
            sum + zip(x, w).reduce(0) { subtotal, pair in
                subtotal + c.derivative(at: (Double(part) + 0.5 + pair.0 * 0.5) / 4).matchMagnitude * pair.1 / 8
            }
        }
    }
    static func flatten(_ ring: MatchRing, tolerance: Double) -> [Point2D] {
        var result: [Point2D] = [ring.spans[0].curve.start]
        func append(_ c: CubicBezier, depth: Int) {
            let d = c.end - c.start
            let reach = max(abs((c.control1 - c.start).cross(d)), abs((c.control2 - c.start).cross(d))) / max(d.matchMagnitude, 1e-12)
            let polygon = c.start.matchDistance(to: c.control1) + c.control1.matchDistance(to: c.control2) + c.control2.matchDistance(to: c.end)
            if depth == 12 || (reach <= tolerance && polygon <= d.matchMagnitude + tolerance * 2) {
                result.append(c.end)
            } else {
                let (a, b) = c.split(at: 0.5); append(a, depth: depth + 1); append(b, depth: depth + 1)
            }
        }
        for s in ring.spans {
            if s.line { result.append(s.curve.end) } else { append(s.curve, depth: 0) }
        }
        return result
    }
    static func distance(_ p: Point2D, to poly: [Point2D]) -> Double {
        zip(poly, poly.dropFirst()).reduce(Double.infinity) { best, edge in
            let d = edge.1 - edge.0
            let t = min(1, max(0, (p - edge.0).dot(d) / max(d.dot(d), 1e-24)))
            return min(best, p.matchDistance(to: edge.0 + d * t))
        }
    }
    static func deviation(_ a: MatchRing, _ b: MatchRing, tolerance: Double) -> Double {
        let flatness = max(1e-7, tolerance / 32)
        let pa = flatten(a, tolerance: flatness), pb = flatten(b, tolerance: flatness)
        return max(pa.map { distance($0, to: pb) }.max() ?? 0, pb.map { distance($0, to: pa) }.max() ?? 0) + flatness * 2
    }
    static func depths(_ rings: [MatchRing]) -> [Int] {
        let polygons = rings.map { flatten($0, tolerance: 0.05) }
        return rings.indices.map { i in
            rings.indices.filter { j in i != j && CleanupDirection.pointInPolygon(rings[i].spans[0].curve.start, polygon: polygons[j]) }.count
        }
    }
    static func validate(_ ring: MatchRing, unitsPerEm: Double, context: MatchGeometryContext = .init()) throws {
        guard ring.spans.count >= 3, ring.spans.count <= 1024, abs(ring.area) > 1e-9 else {
            throw MasterMatchError.geometry("degenerate or oversized contour")
        }
        for s in ring.spans {
            guard s.curve.isFinite, s.curve.start.matchDistance(to: s.curve.end) > 1e-9 else {
                throw MasterMatchError.geometry("non-finite or zero-length segment")
            }
            if !s.line && !controlled(s.curve) {
                throw MasterMatchError.geometry("uncontrolled cubic handles")
            }
        }
        let points = flatten(ring, tolerance: unitsPerEm / 20000)
        guard points.count <= 16384 else { throw MasterMatchError.geometry("flattening resource limit") }
        let edges = Array(zip(points, points.dropFirst()))
        for i in edges.indices {
            guard i + 2 < edges.count else { continue }
            for j in (i + 2)..<edges.count where !(i == 0 && j == edges.count - 1) {
                let a = edges[i], b = edges[j]
                if max(a.0.x, a.1.x) < min(b.0.x, b.1.x) || max(b.0.x, b.1.x) < min(a.0.x, a.1.x)
                    || max(a.0.y, a.1.y) < min(b.0.y, b.1.y) || max(b.0.y, b.1.y) < min(a.0.y, a.1.y) { continue }
                let d = a.1 - a.0, e = b.1 - b.0
                if d.cross(b.0 - a.0) * d.cross(b.1 - a.0) < -1e-12
                    && e.cross(a.0 - b.0) * e.cross(a.1 - b.0) < -1e-12 {
                    let located = diagnosticEdges(ring, tolerance: unitsPerEm / 20000, contour: context.contour)
                    var diagnostic = context.diagnostic("self-intersection", code: "self-intersection")
                    diagnostic.locations = [located[i].location, located[j].location]
                    let t = (b.0-a.0).cross(e) / d.cross(e)
                    let point = a.0+d*t
                    diagnostic.coordinates = [point.x, point.y]
                    diagnostic.classification = "crossing"
                    diagnostic.approximationTolerance = unitsPerEm / 20000
                    throw MasterMatchError.geometryDiagnostic(diagnostic)
                }
            }
        }
    }
}
