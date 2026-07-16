import Foundation
import DesignFlowKernel

public struct OpAmpMetricEvaluator: Sendable {
    public init() {}

    public func evaluate(
        spec: OpAmpSpec,
        crossArtifactEvaluation: FlowCrossArtifactEvaluation
    ) -> OpAmpEvaluationReport {
        let observations = observationsByMetric(from: crossArtifactEvaluation.channelResults)
        return evaluate(
            spec: spec,
            observedMetrics: observations.values.sorted { $0.metricID.rawValue < $1.metricID.rawValue },
            sourceChannelIDs: Dictionary(uniqueKeysWithValues: observations.map { ($0.key, [$0.key.rawValue]) }),
            reportID: "\(spec.specID)-opamp-evaluation"
        )
    }

    public func evaluate(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult
    ) -> OpAmpEvaluationReport {
        evaluate(
            spec: spec,
            observedMetrics: sizingResult.estimatedMetrics,
            sourceChannelIDs: Dictionary(uniqueKeysWithValues: sizingResult.estimatedMetrics.map { ($0.metricID, ["sizing-estimate"]) }),
            reportID: "\(sizingResult.resultID)-evaluation"
        )
    }

    public func evaluate(
        spec: OpAmpSpec,
        observedMetrics: [OpAmpEstimatedMetric],
        sourceChannelIDs: [OpAmpMetricID: [String]] = [:],
        reportID: String
    ) -> OpAmpEvaluationReport {
        let metricMap = Dictionary(uniqueKeysWithValues: observedMetrics.map { ($0.metricID, $0) })
        var diagnostics: [OpAmpDesignDiagnostic] = []
        let results = spec.requirements.map { requirement in
            requirementResult(
                requirement: requirement,
                observed: metricMap[requirement.metricID],
                sourceChannelIDs: sourceChannelIDs[requirement.metricID, default: []]
            )
        }

        let failed = results.filter { $0.status == .failed }
        let missing = results.filter { $0.status == .missing }
        if !missing.isEmpty {
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.evaluation.missing-metrics",
                message: "The op-amp evaluation is missing \(missing.count) required metric(s).",
                relatedMetricIDs: missing.map(\.metricID),
                suggestedActions: ["run-required-simulation-analyses", "attach-artifact-envelopes"]
            ))
        }
        if !failed.isEmpty {
            diagnostics.append(.init(
                severity: .error,
                code: "opamp.evaluation.failed-requirements",
                message: "\(failed.count) op-amp requirement(s) failed.",
                relatedMetricIDs: failed.map(\.metricID),
                suggestedActions: stableUnique(failed.flatMap(\.suggestedActions))
            ))
        }

        return OpAmpEvaluationReport(
            reportID: reportID,
            specID: spec.specID,
            status: failed.isEmpty && missing.isEmpty ? "passed" : failed.isEmpty ? "incomplete" : "failed",
            requirementResults: results,
            observedMetrics: observedMetrics,
            diagnostics: diagnostics
        )
    }

    private func requirementResult(
        requirement: OpAmpSpec.Requirement,
        observed: OpAmpEstimatedMetric?,
        sourceChannelIDs: [String]
    ) -> OpAmpEvaluationReport.RequirementResult {
        guard let observed else {
            return OpAmpEvaluationReport.RequirementResult(
                metricID: requirement.metricID,
                status: .missing,
                requiredRelation: requirement.relation,
                targetValue: requirement.value,
                upperValue: requirement.upperValue,
                unit: requirement.unit,
                failureClassifications: ["missing-measurement"],
                suggestedActions: ["run-\(analysisName(for: requirement.metricID))-analysis"]
            )
        }
        let residual = residualValue(observed.value, requirement: requirement)
        let passed = passes(observed.value, requirement: requirement)
        return OpAmpEvaluationReport.RequirementResult(
            metricID: requirement.metricID,
            status: passed ? .passed : .failed,
            requiredRelation: requirement.relation,
            targetValue: requirement.value,
            upperValue: requirement.upperValue,
            observedValue: observed.value,
            residual: residual,
            unit: requirement.unit,
            sourceChannelIDs: sourceChannelIDs,
            failureClassifications: passed ? [] : classifications(for: requirement.metricID),
            suggestedActions: passed ? [] : suggestedActions(for: requirement.metricID)
        )
    }

    private func observationsByMetric(
        from channelResults: [FlowEvaluationChannelResult]
    ) -> [OpAmpMetricID: OpAmpEstimatedMetric] {
        var observations: [OpAmpMetricID: OpAmpEstimatedMetric] = [:]
        for channel in channelResults {
            guard let metricID = metricID(for: channel.channelID),
                  let value = numericValue(channel.observedValue) else {
                continue
            }
            observations[metricID] = OpAmpEstimatedMetric(
                metricID: metricID,
                value: value,
                unit: unit(for: metricID),
                method: "cross-artifact channel \(channel.channelID)"
            )
        }
        return observations
    }

    private func metricID(for channelID: String) -> OpAmpMetricID? {
        if let direct = OpAmpMetricID(rawValue: channelID) {
            return direct
        }
        if channelID.hasPrefix("metric.") {
            let trimmed = String(channelID.dropFirst("metric.".count))
                .replacingOccurrences(of: ".coverage", with: "")
            return OpAmpMetricID(rawValue: trimmed)
        }
        if channelID.hasPrefix("observation.") {
            let trimmed = String(channelID.dropFirst("observation.".count))
                .replacingOccurrences(of: ".availability", with: "")
            return OpAmpMetricID(rawValue: trimmed)
        }
        return nil
    }

    private func numericValue(_ value: FlowMetricValue?) -> Double? {
        guard let value else {
            return nil
        }
        switch value {
        case .scalar(let number), .quantity(let number, _):
            return number.isFinite ? number : nil
        case .text(let text):
            guard let number = Double(text), number.isFinite else {
                return nil
            }
            return number
        case .boolean, .vector:
            return nil
        }
    }

    private func passes(_ value: Double, requirement: OpAmpSpec.Requirement) -> Bool {
        let tolerance = requirement.tolerance ?? 0
        switch requirement.relation {
        case .atLeast:
            return value + tolerance >= requirement.value
        case .atMost:
            return value - tolerance <= requirement.value
        case .between:
            guard let upper = requirement.upperValue else {
                return false
            }
            return value + tolerance >= requirement.value && value - tolerance <= upper
        case .equal:
            return abs(value - requirement.value) <= tolerance
        }
    }

    private func residualValue(_ value: Double, requirement: OpAmpSpec.Requirement) -> Double {
        switch requirement.relation {
        case .atLeast:
            return value - requirement.value
        case .atMost:
            return requirement.value - value
        case .between:
            guard let upper = requirement.upperValue else {
                return -.infinity
            }
            return min(value - requirement.value, upper - value)
        case .equal:
            return -abs(value - requirement.value)
        }
    }

    private func classifications(for metricID: OpAmpMetricID) -> [String] {
        switch metricID {
        case .dcGainDB:
            ["insufficient-open-loop-gain", "low-output-resistance-or-gm"]
        case .unityGainFrequencyHz:
            ["insufficient-bandwidth", "input-gm-or-compensation-limited"]
        case .phaseMarginDegrees:
            ["stability-risk", "nondominant-pole-too-low"]
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            ["slew-rate-limited", "bias-current-or-capacitance-limited"]
        case .cmrrDB:
            ["common-mode-rejection-limited", "input-pair-or-tail-source-mismatch"]
        case .psrrPositiveDB, .psrrNegativeDB:
            ["supply-rejection-limited", "bias-or-cascode-isolation-limited"]
        case .inputReferredNoiseVPerRootHz:
            ["noise-too-high", "input-gm-or-device-area-limited"]
        case .inputOffsetVoltage:
            ["offset-too-high", "matching-or-device-area-limited"]
        case .staticPowerW, .quiescentCurrentA:
            ["power-too-high", "bias-current-too-high"]
        default:
            ["metric-target-missed"]
        }
    }

    private func suggestedActions(for metricID: OpAmpMetricID) -> [String] {
        switch metricID {
        case .dcGainDB:
            ["increase-channel-length", "increase-gm", "use-cascode-topology"]
        case .unityGainFrequencyHz:
            ["increase-input-pair-current", "reduce-compensation-capacitance", "reduce-load-capacitance"]
        case .phaseMarginDegrees:
            ["increase-compensation-capacitance", "increase-second-stage-gm", "move-nondominant-pole-up"]
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            ["increase-slew-current", "reduce-compensation-capacitance", "reduce-load-capacitance"]
        case .cmrrDB:
            ["improve-input-pair-common-centroid", "increase-tail-source-output-resistance", "check-common-mode-bias"]
        case .psrrPositiveDB, .psrrNegativeDB:
            ["increase-bias-isolation", "use-cascode-current-source", "add-supply-filtering"]
        case .inputReferredNoiseVPerRootHz:
            ["increase-input-gm", "increase-input-device-area", "reduce-noisy-bias-current"]
        case .inputOffsetVoltage:
            ["increase-input-device-area", "enforce-common-centroid-layout", "rebalance-input-pair"]
        case .staticPowerW, .quiescentCurrentA:
            ["reduce-bias-current", "relax-speed-target", "choose-lower-power-topology"]
        default:
            ["inspect-measurement-and-sizing"]
        }
    }

    private func analysisName(for metricID: OpAmpMetricID) -> String {
        switch metricID.rawValue.split(separator: ".").first {
        case "ac":
            "ac"
        case "tran":
            "transient"
        case "noise":
            "noise"
        case "drc":
            "drc"
        case "lvs":
            "lvs"
        case "pex":
            "pex"
        default:
            "simulation"
        }
    }

    private func unit(for metricID: OpAmpMetricID) -> String {
        switch metricID {
        case .dcGainDB, .cmrrDB, .psrrPositiveDB, .psrrNegativeDB, .pexDeltaGainDB:
            "dB"
        case .unityGainFrequencyHz:
            "Hz"
        case .phaseMarginDegrees, .pexDeltaPhaseMarginDegrees:
            "deg"
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            "V/s"
        case .settlingTimeSeconds:
            "s"
        case .inputReferredNoiseVPerRootHz:
            "V/sqrt(Hz)"
        case .inputOffsetVoltage, .outputSwingHighV, .outputSwingLowV, .inputCommonModeMinV, .inputCommonModeMaxV:
            "V"
        case .staticPowerW:
            "W"
        case .quiescentCurrentA:
            "A"
        case .drcViolationCount:
            "count"
        case .lvsStatus:
            "status"
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
