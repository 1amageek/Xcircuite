import CircuiteFoundation
import DesignFlowKernel
import Foundation

struct SimulationSummaryEnvelopeBuilder: Sendable {
    func envelopeReference(
        summary: SimulationRunSummaryReport,
        summaryArtifactID: String,
        stageArtifacts: [ArtifactReference],
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        guard let summaryArtifact = stageArtifacts.first(where: { $0.artifactID == summaryArtifactID }) else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: stageID)
        }
        guard let producer = summaryArtifact.producer,
              producer.build != nil else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "Stage \(stageID) simulation summary artifact requires an attested producer identity."
            )
        }
        let artifactID = summaryArtifact.artifactID

        let hasQualifiedEvidence = hasQualifiedEvidence(context: context, toolID: toolID)
        let toolEvidenceCount = context.healthResults[toolID]?.evidence.count ?? 0
        let confidence = confidence(hasQualifiedEvidence: hasQualifiedEvidence)
        let measurementChannels = measurementObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        )
        let waveformChannels = waveformObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        )
        let criteria = baseCriteria(artifactID: artifactID) + measurementCriteria(summary: summary)
        let channelResults = baseChannelResults(
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            confidence: confidence
        ) + waveformChannelResults(summary: summary, confidence: confidence)
            + measurementChannelResults(summary: summary, confidence: confidence)
        var observationChannels = baseObservationChannels(
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            toolEvidenceCount: toolEvidenceCount,
            hasQualifiedEvidence: hasQualifiedEvidence,
            confidence: confidence
        )
        observationChannels.append(contentsOf: waveformChannels)
        observationChannels.append(contentsOf: measurementChannels)
        let envelope = FlowArtifactEnvelope(
            artifactID: artifactID,
            role: "simulation-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: FlowArtifactProducer(identity: producer),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: FlowEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate simulation measurement evidence for stage readiness.",
                criteria: criteria,
                requiredArtifactRoles: ["simulation-summary", "measurement", "waveform"],
                confidence: FlowEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false)
            ),
            observationSet: FlowObservationSet(
                observationSetID: "\(artifactID)-observations",
                specID: "\(artifactID)-evaluation-spec",
                channels: observationChannels,
                confidence: confidence
            ),
            evaluationResult: FlowEvaluationResult(
                evaluationID: "\(artifactID)-evaluation",
                specID: "\(artifactID)-evaluation-spec",
                status: evaluationStatus(from: gateStatus),
                likelihood: likelihood(from: gateStatus),
                residual: maximumNormalizedResidual(summary: summary, gateStatus: gateStatus),
                confidence: confidence,
                channelResults: channelResults,
                feedbackSignals: feedbackSignals(
                    artifactID: artifactID,
                    summary: summary,
                    gateStatus: gateStatus,
                    confidence: confidence
                ),
                summary: "Simulation summary evaluation ended with gate status \(gateStatus.rawValue)."
            )
        )

        return try await context.persistArtifactEnvelope(envelope)
    }

    private func baseCriteria(artifactID: String) -> [FlowEvaluationCriterion] {
        [
            FlowEvaluationCriterion(
                criterionID: "simulation-gate-status",
                channelID: "simulation-gate-status",
                comparator: .equal,
                target: .text(FlowGateStatus.passed.rawValue)
            ),
            FlowEvaluationCriterion(
                criterionID: "simulation-waveform-variable-count",
                channelID: "simulation-waveform-variable-count",
                comparator: .greaterThan,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "simulation-tool-evidence",
                channelID: "simulation-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .scalar(1),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "simulation-calibration",
                channelID: "simulation-qualified-calibration",
                comparator: .equal,
                target: .boolean(true),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "simulation-summary-artifact",
                channelID: "simulation-summary-artifact-present",
                comparator: .equal,
                target: .boolean(true),
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
        ]
    }

    private func measurementCriteria(
        summary: SimulationRunSummaryReport
    ) -> [FlowEvaluationCriterion] {
        summary.expectations.enumerated().map { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            return FlowEvaluationCriterion(
                criterionID: "\(baseID)-within-tolerance",
                channelID: "\(baseID)-within-tolerance",
                comparator: .equal,
                target: .boolean(true),
                tolerance: expectation.tolerance,
                context: FlowEvaluationContext(
                    metricChannelID: baseID,
                    parameterName: expectation.name,
                    requiredValue: expectation.target
                )
            )
        }
    }

    private func baseObservationChannels(
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        [
            FlowObservationChannel(
                channelID: "simulation-summary-artifact-present",
                status: .observed,
                value: .boolean(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "simulation-gate-status",
                status: .observed,
                value: .text(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                context: FlowEvaluationContext(gateID: "simulation")
            ),
            FlowObservationChannel(
                channelID: "simulation-diagnostic-count",
                status: .observed,
                value: .scalar(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "simulation-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .scalar(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "simulation-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .boolean(hasQualifiedEvidence),
                confidence: confidence
            ),
        ]
    }

    private func waveformObservationChannels(
        summary: SimulationRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        [
            FlowObservationChannel(
                channelID: "simulation-waveform-variable-count",
                status: summary.waveformVariables.isEmpty ? .missing : .observed,
                value: .scalar(Double(summary.waveformVariables.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func measurementObservationChannels(
        summary: SimulationRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        let measurementsByName = Dictionary(
            summary.measurements.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return summary.expectations.enumerated().flatMap { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            let measurement = measurementsByName[expectation.name.lowercased()]
            let valueStatus: FlowObservationChannelStatus = measurement == nil ? .missing : .observed
            let residualStatus: FlowObservationChannelStatus = expectation.residual == nil ? .missing : .observed
            let withinStatus: FlowObservationChannelStatus = expectation.status == "missing" ? .missing : .observed
            return [
                FlowObservationChannel(
                    channelID: "\(baseID)-value",
                    label: expectation.name,
                    status: valueStatus,
                    value: measurement.map { .scalar($0.value) },
                    unit: measurement?.unit,
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: FlowEvaluationContext(
                        parameterName: expectation.name,
                        requiredValue: expectation.target
                    )
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-residual",
                    label: "\(expectation.name) residual",
                    status: residualStatus,
                    value: expectation.residual.map { .scalar($0) },
                    unit: measurement?.unit,
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: FlowEvaluationContext(
                        parameterName: expectation.name,
                        maximumValue: expectation.tolerance
                    )
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-within-tolerance",
                    label: "\(expectation.name) within tolerance",
                    status: withinStatus,
                    value: expectation.status == "missing" ? nil : .boolean(expectation.status == "passed"),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: FlowEvaluationContext(
                        parameterName: expectation.name,
                        maximumValue: expectation.tolerance,
                        requiredValue: expectation.target
                    )
                ),
            ]
        }
    }

    private func baseChannelResults(
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                criterionID: "simulation-gate-status",
                channelID: "simulation-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .text(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            FlowEvaluationChannelResult(
                criterionID: "simulation-summary-artifact",
                channelID: "simulation-summary-artifact-present",
                status: .accepted,
                observedValue: .boolean(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
        ]
    }

    private func waveformChannelResults(
        summary: SimulationRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                criterionID: "simulation-waveform-variable-count",
                channelID: "simulation-waveform-variable-count",
                status: summary.waveformVariables.isEmpty ? .inconclusive : .accepted,
                observedValue: .scalar(Double(summary.waveformVariables.count)),
                residual: summary.waveformVariables.isEmpty ? 1 : 0,
                likelihood: summary.waveformVariables.isEmpty ? 0 : 1,
                confidence: confidence
            ),
        ]
    }

    private func measurementChannelResults(
        summary: SimulationRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        summary.expectations.enumerated().map { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            return FlowEvaluationChannelResult(
                criterionID: "\(baseID)-within-tolerance",
                channelID: "\(baseID)-within-tolerance",
                status: evaluationStatus(from: expectation.status),
                observedValue: expectation.status == "missing" ? nil : .boolean(expectation.status == "passed"),
                residual: normalizedResidual(for: expectation),
                likelihood: likelihood(for: expectation),
                confidence: confidence,
                context: FlowEvaluationContext(
                    parameterName: expectation.name,
                    maximumValue: expectation.tolerance,
                    requiredValue: expectation.target
                )
            )
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: SimulationRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        guard gateStatus != .passed else {
            return [
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-continue",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "simulation-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "Simulation summary is usable as downstream evidence.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["continue-flow"],
                    confidence: confidence
                ),
            ]
        }

        return summary.expectations.enumerated()
            .filter { _, expectation in expectation.status != "passed" }
            .map { index, expectation in
                let baseID = measurementChannelBase(index: index, name: expectation.name)
                let isMissing = expectation.status == "missing"
                return FlowFeedbackSignal(
                    signalID: "\(baseID)-feedback",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "\(baseID)-within-tolerance",
                    routingLevel: isMissing ? .structureMapping : .localSurface,
                    severity: .error,
                    summary: isMissing
                        ? "Simulation measurement \(expectation.name) is missing."
                        : "Simulation measurement \(expectation.name) is outside tolerance.",
                    residual: normalizedResidual(for: expectation),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: isMissing
                        ? ["inspect-measurement-definition", "update-simulation-observation"]
                        : ["inspect-simulation-measurement", "adjust-design-parameters"],
                    confidence: confidence
                )
            }
    }

    private func dependencies(
        from artifacts: [ArtifactReference],
        excluding summaryArtifact: ArtifactReference
    ) -> [FlowArtifactDependency] {
        artifacts
            .filter { $0.path != summaryArtifact.path }
            .map { artifact in
                FlowArtifactDependency(
                    artifactID: artifact.artifactID,
                    path: artifact.path,
                    role: artifact.artifactID,
                    required: true
                )
            }
    }

    private func hasQualifiedEvidence(context: FlowExecutionContext, toolID: String) -> Bool {
        guard let descriptor = context.toolRegistry.descriptor(toolID: toolID),
              descriptor.trustProfile.level >= .corpusChecked,
              context.healthResults[toolID]?.status == .passed else {
            return false
        }
        return descriptor.trustProfile.evidence.contains(where: \.hasVerifiableArtifactBinding)
    }

    private func confidence(hasQualifiedEvidence: Bool) -> FlowEvidenceConfidence {
        if hasQualifiedEvidence {
            return FlowEvidenceConfidence(
                value: 0.8,
                posteriorVariance: 0.2,
                calibrationCoefficient: 0.7,
                calibrated: true
            )
        }
        return FlowEvidenceConfidence(
            value: 0.35,
            posteriorVariance: 0.65,
            calibrationCoefficient: 0,
            calibrated: false
        )
    }

    private func maximumNormalizedResidual(
        summary: SimulationRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> Double {
        guard gateStatus == .passed || !summary.expectations.isEmpty else {
            return 1
        }
        return summary.expectations
            .map(normalizedResidual)
            .compactMap { $0 }
            .max() ?? (gateStatus == .passed ? 0 : 1)
    }

    private func normalizedResidual(
        for expectation: SimulationRunSummaryReport.ExpectationResult
    ) -> Double? {
        guard let residual = expectation.residual else {
            return nil
        }
        guard expectation.tolerance > 0 else {
            return residual
        }
        return residual / expectation.tolerance
    }

    private func likelihood(for expectation: SimulationRunSummaryReport.ExpectationResult) -> Double? {
        guard let residual = normalizedResidual(for: expectation) else {
            return nil
        }
        return max(0, min(1, 1 - residual))
    }

    private func evaluationStatus(from status: String) -> FlowEvaluationStatus {
        switch status {
        case "passed":
            .accepted
        case "failed":
            .rejected
        default:
            .inconclusive
        }
    }

    private func evaluationStatus(from status: FlowGateStatus) -> FlowEvaluationStatus {
        switch status {
        case .passed, .waived:
            .accepted
        case .failed:
            .rejected
        case .incomplete:
            .inconclusive
        case .blocked:
            .blocked
        }
    }

    private func likelihood(from status: FlowGateStatus) -> Double {
        switch status {
        case .passed:
            1
        case .waived:
            0.8
        case .incomplete:
            0.5
        case .failed:
            0
        case .blocked:
            0
        }
    }

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> FlowRunDiagnostic {
        FlowRunDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionSeverity(
        _ severity: FlowDiagnosticSeverity
    ) -> FlowRunDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func measurementChannelBase(index: Int, name: String) -> String {
        "simulation-measurement-\(index)-\(slug(name))"
    }

    private func slug(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let compact = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return compact.isEmpty ? "measurement" : compact
    }
}
