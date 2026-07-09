import Foundation

public struct OpAmpPostLayoutComparator: Sendable {
    public init() {}

    public func compare(
        spec: OpAmpSpec,
        preLayout: OpAmpEvaluationReport,
        postLayout: OpAmpEvaluationReport,
        maximumRelativeDegradation: Double = 0.2
    ) -> OpAmpPostLayoutComparisonReport {
        let preMetrics = Dictionary(uniqueKeysWithValues: preLayout.observedMetrics.map { ($0.metricID, $0) })
        let postMetrics = Dictionary(uniqueKeysWithValues: postLayout.observedMetrics.map { ($0.metricID, $0) })
        let metricIDs = stableMetricIDs(spec: spec, preMetrics: preMetrics, postMetrics: postMetrics)
        var diagnostics: [OpAmpDesignDiagnostic] = []
        let deltas = metricIDs.map { metricID in
            delta(
                metricID: metricID,
                pre: preMetrics[metricID],
                post: postMetrics[metricID],
                spec: spec,
                maximumRelativeDegradation: maximumRelativeDegradation
            )
        }
        let degraded = deltas.filter { $0.status == "degraded" || $0.status == "missing-post-layout" }
        if !degraded.isEmpty {
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.post-layout.degradation",
                message: "\(degraded.count) metric(s) degraded after layout/PEX.",
                relatedMetricIDs: degraded.map(\.metricID),
                suggestedActions: ["inspect-pex-parasitics", "tighten-layout-constraints", "rerun-post-layout-simulation"]
            ))
        }
        let postFailed = postLayout.requirementResults.filter { $0.status == .failed }
        if !postFailed.isEmpty {
            diagnostics.append(.init(
                severity: .error,
                code: "opamp.post-layout.spec-failure",
                message: "Post-layout evaluation fails \(postFailed.count) requirement(s).",
                relatedMetricIDs: postFailed.map(\.metricID),
                suggestedActions: stableUnique(postFailed.flatMap(\.suggestedActions))
            ))
        }
        let actions = stableUnique(diagnostics.flatMap(\.suggestedActions))
        return OpAmpPostLayoutComparisonReport(
            reportID: "\(spec.specID)-post-layout-comparison",
            specID: spec.specID,
            status: postFailed.isEmpty && degraded.isEmpty ? "passed" : postFailed.isEmpty ? "needsReview" : "failed",
            deltas: deltas,
            diagnostics: diagnostics,
            suggestedActions: actions
        )
    }

    private func delta(
        metricID: OpAmpMetricID,
        pre: OpAmpEstimatedMetric?,
        post: OpAmpEstimatedMetric?,
        spec: OpAmpSpec,
        maximumRelativeDegradation: Double
    ) -> OpAmpPostLayoutComparisonReport.MetricDelta {
        guard let pre, let post else {
            return OpAmpPostLayoutComparisonReport.MetricDelta(
                metricID: metricID,
                preLayoutValue: pre?.value,
                postLayoutValue: post?.value,
                delta: nil,
                relativeDelta: nil,
                unit: pre?.unit ?? post?.unit ?? "",
                status: post == nil ? "missing-post-layout" : "missing-pre-layout",
                classification: "missing-comparison-input"
            )
        }
        let delta = post.value - pre.value
        let relative = abs(delta) / max(abs(pre.value), 1.0e-30)
        let lowerIsBetter = spec.requirement(for: metricID)?.relation == .atMost
        let degraded = lowerIsBetter ? delta > 0 : delta < 0
        let unacceptable = degraded && relative > maximumRelativeDegradation
        return OpAmpPostLayoutComparisonReport.MetricDelta(
            metricID: metricID,
            preLayoutValue: pre.value,
            postLayoutValue: post.value,
            delta: delta,
            relativeDelta: relative,
            unit: post.unit,
            status: unacceptable ? "degraded" : "accepted",
            classification: unacceptable ? classification(for: metricID) : "within-degradation-budget"
        )
    }

    private func stableMetricIDs(
        spec: OpAmpSpec,
        preMetrics: [OpAmpMetricID: OpAmpEstimatedMetric],
        postMetrics: [OpAmpMetricID: OpAmpEstimatedMetric]
    ) -> [OpAmpMetricID] {
        var result: [OpAmpMetricID] = []
        for metricID in spec.requirements.map(\.metricID) + preMetrics.keys + postMetrics.keys {
            if !result.contains(metricID) {
                result.append(metricID)
            }
        }
        return result
    }

    private func classification(for metricID: OpAmpMetricID) -> String {
        switch metricID {
        case .dcGainDB, .pexDeltaGainDB:
            "parasitic-loading-or-output-resistance-degradation"
        case .unityGainFrequencyHz, .phaseMarginDegrees, .pexDeltaPhaseMarginDegrees:
            "parasitic-capacitance-stability-degradation"
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            "load-or-compensation-parasitic-slew-degradation"
        case .inputOffsetVoltage:
            "layout-mismatch-offset-degradation"
        case .inputReferredNoiseVPerRootHz:
            "layout-or-bias-noise-degradation"
        default:
            "post-layout-metric-degradation"
        }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
