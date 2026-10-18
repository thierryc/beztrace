// Copyright 2026 beztrace contributors
// SPDX-License-Identifier: Apache-2.0 OR MIT
import Foundation

/// One post-fit projection, shared by vector and raster matching. The caller
/// owns original-source evidence; no intermediate fit resets the error budget.
enum MatchSmoothing {
    static func apply(_ input: MasterMatchResult,
                      measure: @escaping (Outline) throws -> PairDeviation) throws -> MasterMatchResult {
        guard input.options.smoothJoins else { return input }
        let tolerance=input.options.fitTolerance
        let smoothed=try JointMasterSmoother.smooth(.init(reference:input.reference.outline,
            target:input.target.outline,sourceTarget:input.sourceMasters[1].outline,
            unitsPerEm:input.unitsPerEm,fitTolerance:tolerance),sourceMeasurement:measure)
        guard smoothed.report.status != .refused else {
            throw MasterMatchError.fitDiagnostic(.init(code:"joint-smoothing-refused",
                message:smoothed.report.reason ?? "Joint smoothing could not meet the unchanged limits",
                stage:"joint-smoothing",role:"target",masterID:input.target.id,
                measuredDeviation:smoothed.report.proposalDeviation?.upperBound,
                allowedDeviation:tolerance,cause:"verified-joint-smoothing-not-established"))
        }
        var result=input
        result.target.outline=smoothed.target;result.jointSmoothing=smoothed.report
        result.warnings.removeAll { $0 == "Linear interpolation has sampled tangency residuals; native HOI review is required."
            || $0 == "Sampled smooth joins require native HOI review." }
        // Reuse the completed 201-position acceptance sweep, without running it
        // again merely to reconstruct the matching transport report.
        result.interpolation = .init(sampleCount:201,
            maximumTangencyResidual:smoothed.report.afterMaximumTangencyResidual!,issues:[])
        let upper=smoothed.report.proposalDeviation!.upperBound
        for i in result.contours.indices { result.contours[i].maximumTargetDeviation=upper }
        return result
    }

    static func pending() -> InterpolationReport {
        .init(sampleCount:0,maximumTangencyResidual:0,issues:[])
    }
}
