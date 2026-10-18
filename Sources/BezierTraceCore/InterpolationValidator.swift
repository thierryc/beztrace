// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT

import Foundation

public enum InterpolationValidator {
    private static func tangencyResidual(_ a: Point2D, _ p: Point2D, _ b: Point2D) -> Double? {
        let incoming = p-a, outgoing = b-p
        guard incoming.matchMagnitude >= 1e-9, outgoing.matchMagnitude >= 1e-9,
              incoming.dot(outgoing) > 0 else { return nil }
        let d = b-a
        return abs(incoming.cross(d)) / max(d.matchMagnitude, 1e-12)
    }

    /// Diagnostic only, for an already correspondence-checked pair. Acceptance
    /// still requires validate(), including geometry and nesting at every step.
    static func maximumTangencyResidual(reference: Outline, target: Outline, intervals: Int) -> Double {
        var peak = 0.0
        for step in 0...intervals {
            let factor = Double(step) / Double(intervals)
            for (a, b) in zip(reference.contours, target.contours) {
                func point(_ i: Int) -> Point2D {
                    .init(x:a.nodes[i].x+(b.nodes[i].x-a.nodes[i].x)*factor,
                          y:a.nodes[i].y+(b.nodes[i].y-a.nodes[i].y)*factor)
                }
                let count = a.nodes.count
                for j in a.nodes.indices where a.nodes[j].smooth && b.nodes[j].smooth {
                    if let residual = tangencyResidual(point((j+count-1)%count),point(j),point((j+1)%count)) {
                        peak = max(peak,residual)
                    }
                }
            }
        }
        return peak
    }

    public static func interpolate(reference: Outline, target: Outline, factor: Double) throws -> Outline {
        guard factor.isFinite, (0...1).contains(factor), reference.contours.count == target.contours.count else {
            throw MasterMatchError.invalid("interpolation factor or contour correspondence")
        }
        return Outline(contours: try zip(reference.contours, target.contours).map { a, b in
            guard a.closed && b.closed, a.nodes.count == b.nodes.count, a.nodes.map(\.type) == b.nodes.map(\.type) else {
                throw MasterMatchError.topology("node count or types differ")
            }
            return Contour(nodes: zip(a.nodes, b.nodes).map { p, q in
                Node(x: p.x + (q.x - p.x) * factor, y: p.y + (q.y - p.y) * factor,
                     type: p.type, smooth: p.smooth && q.smooth)
            })
        })
    }

    public static func validate(reference: Outline, target: Outline, unitsPerEm: Double = 1000,
                                intervals: Int = 100) throws -> InterpolationReport {
        guard unitsPerEm.isFinite, (16...16384).contains(unitsPerEm), (2...1000).contains(intervals),
              !reference.contours.isEmpty, reference.contours.count <= 64,
              reference.contours.reduce(0, { $0 + $1.nodes.count }) <= 4096 else {
            throw MasterMatchError.invalid("interpolation validation limits")
        }
        let expected = MatchGeometry.depths(try reference.contours.map(MatchRing.init))
        var peak = 0.0, issues: [InterpolationIssue] = []
        for step in 0...intervals {
            let factor = Double(step) / Double(intervals)
            let outline = try interpolate(reference: reference, target: target, factor: factor)
            var rings: [MatchRing] = []
            for (i, contour) in outline.contours.enumerated() {
                do {
                    let ring = try MatchRing(contour); try MatchGeometry.validate(ring, unitsPerEm: unitsPerEm,context:.init(stage:"interpolation",role:"interpolated",contour:i,interpolationFactor:factor))
                    rings.append(ring)
                } catch {
                    issues.append(.init(factor: factor, contour: i, node: nil, message: String(describing: error),diagnostic:(error as? MasterMatchError)?.diagnostic))
                    continue
                }
                for j in contour.nodes.indices where contour.nodes[j].smooth {
                    let nodes = contour.nodes, count = nodes.count
                    let a = nodes[(j + count - 1) % count].point, p = nodes[j].point, b = nodes[(j + 1) % count].point
                    guard let residual = tangencyResidual(a,p,b) else {
                        issues.append(.init(factor:factor,contour:i,node:j,message:"folded or degenerate smooth join"))
                        continue
                    }
                    peak = max(peak, residual)
                    if residual > unitsPerEm / 1000 && issues.count < 2048 {
                        issues.append(.init(factor: factor, contour: i, node: j, message: "smooth join tangency residual"))
                    }
                }
            }
            if rings.count == expected.count && MatchGeometry.depths(rings) != expected {
                issues.append(.init(factor: factor, contour: 0, node: nil, message: "counter nesting changes"))
            }
        }
        return InterpolationReport(sampleCount: intervals + 1, maximumTangencyResidual: peak, issues: issues)
    }
}
