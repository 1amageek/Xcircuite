import Foundation

public struct OpAmpSimulationMetricExtractionMerger: Sendable {
    public init() {}

    public func merge(
        _ extractions: [OpAmpSimulationMetricExtraction],
        sourceKind: String = "xcircuite-opamp-metric-extraction-merge"
    ) throws -> OpAmpSimulationMetricExtraction {
        guard !extractions.isEmpty else {
            throw OpAmpSimulationMetricExtractionMergeError.emptyInputs
        }

        var entriesByMetricID: [OpAmpMetricID: [MetricEntry]] = [:]
        var unmappedMeasurements: [OpAmpSimulationMetricExtraction.UnmappedMeasurement] = []
        var diagnostics: [OpAmpDesignDiagnostic] = []
        var sourceLabels: [String] = []
        var sourceStatuses: [String] = []

        for (sourceIndex, extraction) in extractions.enumerated() {
            let label = sourceLabel(for: extraction, at: sourceIndex)
            sourceLabels.append(label)
            if let status = extraction.sourceStatus {
                sourceStatuses.append(status)
            }
            diagnostics.append(contentsOf: extraction.diagnostics)
            unmappedMeasurements.append(contentsOf: extraction.unmappedMeasurements.map {
                OpAmpSimulationMetricExtraction.UnmappedMeasurement(
                    name: "\(label):\($0.name)",
                    value: $0.value,
                    unit: $0.unit
                )
            })

            for metric in extraction.observedMetrics {
                guard metric.value.isFinite else {
                    diagnostics.append(.init(
                        severity: .warning,
                        code: "opamp.metric-extraction-merge.non-finite-metric",
                        message: "Dropped non-finite metric \(metric.metricID.rawValue) from \(label).",
                        relatedMetricIDs: [metric.metricID],
                        suggestedActions: ["inspect-source-metric-extraction"]
                    ))
                    continue
                }
                let enrichedMetric = OpAmpEstimatedMetric(
                    metricID: metric.metricID,
                    value: metric.value,
                    unit: metric.unit,
                    method: "\(metric.method) [source: \(label)]"
                )
                entriesByMetricID[metric.metricID, default: []].append(MetricEntry(
                    sourceLabel: label,
                    metric: enrichedMetric
                ))
            }
        }

        var observedMetrics: [OpAmpEstimatedMetric] = []
        for metricID in entriesByMetricID.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let entries = entriesByMetricID[metricID], let selected = entries.last else {
                continue
            }
            appendDuplicateDiagnostics(
                metricID: metricID,
                entries: entries,
                selected: selected,
                diagnostics: &diagnostics
            )
            observedMetrics.append(selected.metric)
        }

        diagnostics.append(.init(
            severity: .info,
            code: "opamp.metric-extraction-merge.summary",
            message: "Merged \(extractions.count) op-amp metric extraction artifact(s) into \(observedMetrics.count) unique metric(s).",
            relatedMetricIDs: observedMetrics.map(\.metricID),
            suggestedActions: ["evaluate-merged-opamp-metrics"]
        ))

        return OpAmpSimulationMetricExtraction(
            sourceKind: sourceKind,
            sourceStatus: mergedStatus(sourceStatuses: sourceStatuses, diagnostics: diagnostics),
            sourceAnalysisLabel: stableUnique(sourceLabels).joined(separator: ","),
            observedMetrics: observedMetrics,
            unmappedMeasurements: unmappedMeasurements,
            diagnostics: diagnostics
        )
    }

    private func appendDuplicateDiagnostics(
        metricID: OpAmpMetricID,
        entries: [MetricEntry],
        selected: MetricEntry,
        diagnostics: inout [OpAmpDesignDiagnostic]
    ) {
        guard entries.count > 1 else {
            return
        }
        let conflicting = entries.contains { !equivalent($0.metric, selected.metric) }
        if conflicting {
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.metric-extraction-merge.conflicting-metric",
                message: "Metric \(metricID.rawValue) appeared in multiple extraction artifacts with different values or units; \(selected.sourceLabel) was selected by input order.",
                relatedMetricIDs: [metricID],
                suggestedActions: ["inspect-conflicting-metric-sources", "choose-explicit-extraction-order"]
            ))
        } else {
            diagnostics.append(.init(
                severity: .info,
                code: "opamp.metric-extraction-merge.duplicate-equivalent-metric",
                message: "Metric \(metricID.rawValue) appeared in multiple extraction artifacts with equivalent values; \(selected.sourceLabel) was retained.",
                relatedMetricIDs: [metricID],
                suggestedActions: ["deduplicate-extraction-inputs"]
            ))
        }
    }

    private func sourceLabel(
        for extraction: OpAmpSimulationMetricExtraction,
        at index: Int
    ) -> String {
        if let analysisLabel = extraction.sourceAnalysisLabel, !analysisLabel.isEmpty {
            return "\(extraction.sourceKind):\(analysisLabel)"
        }
        return "\(extraction.sourceKind):\(index + 1)"
    }

    private func equivalent(_ lhs: OpAmpEstimatedMetric, _ rhs: OpAmpEstimatedMetric) -> Bool {
        guard lhs.unit == rhs.unit else {
            return false
        }
        let scale = max(abs(lhs.value), abs(rhs.value), 1.0)
        return abs(lhs.value - rhs.value) <= scale * 1.0e-9
    }

    private func mergedStatus(
        sourceStatuses: [String],
        diagnostics: [OpAmpDesignDiagnostic]
    ) -> String {
        let normalizedStatuses = Set(sourceStatuses.map { $0.lowercased() })
        if normalizedStatuses.contains(where: { ["failed", "failure", "error"].contains($0) }) ||
            diagnostics.contains(where: { $0.severity == .error }) {
            return "failed"
        }
        if normalizedStatuses.contains(where: { !["passed", "ok", "succeeded"].contains($0) }) ||
            diagnostics.contains(where: { $0.severity == .warning }) {
            return "warning"
        }
        return "passed"
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

private struct MetricEntry: Sendable, Hashable {
    var sourceLabel: String
    var metric: OpAmpEstimatedMetric
}
