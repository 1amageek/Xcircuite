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
    ) throws -> ArtifactReference {
        guard let summaryArtifact = stageArtifacts.first(where: { $0.artifactID == summaryArtifactID }) else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: stageID)
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
        let envelope = XcircuiteArtifactEnvelope(
            artifactID: artifactID,
            role: "simulation-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: XcircuiteArtifactProducer(
                producerID: toolID,
                toolID: toolID
            ),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: XcircuiteEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate simulation measurement evidence for stage readiness.",
                criteria: criteria,
                requiredArtifactRoles: ["simulation-summary", "measurement", "waveform"],
                confidence: XcircuiteEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false),
                metadata: [
                    "analysis": .string(summary.summary.analysis),
                    "expectationCount": .number(Double(summary.summary.expectationCount)),
                ]
            ),
            observationSet: XcircuiteObservationSet(
                observationSetID: "\(artifactID)-observations",
                specID: "\(artifactID)-evaluation-spec",
                channels: baseObservationChannels(
                    artifactID: artifactID,
                    gateStatus: gateStatus,
                    diagnostics: diagnostics,
                    toolEvidenceCount: toolEvidenceCount,
                    hasQualifiedEvidence: hasQualifiedEvidence,
                    confidence: confidence
                ) + waveformChannels + measurementChannels,
                confidence: confidence,
                metadata: [
                    "analysis": .string(summary.summary.analysis),
                    "measurementCount": .number(Double(summary.summary.measurementCount)),
                    "waveformVariableCount": .number(Double(summary.summary.waveformVariableCount)),
                ]
            ),
            evaluationResult: XcircuiteEvaluationResult(
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
                summary: "Simulation summary evaluation ended with gate status \(gateStatus.rawValue).",
                metadata: [
                    "analysis": .string(summary.summary.analysis),
                    "failedExpectationCount": .number(Double(summary.summary.failedExpectationCount)),
                ]
            ),
            metadata: [
                "gateID": .string("simulation"),
                "gateStatus": .string(gateStatus.rawValue),
                "stageID": .string(stageID),
                "toolID": .string(toolID),
            ]
        )

        return try context.storage.writeArtifactEnvelope(
            envelope,
            runID: context.runID,
            inProjectAt: context.projectRoot
        )
    }

    private func baseCriteria(artifactID: String) -> [XcircuiteEvaluationCriterion] {
        [
            XcircuiteEvaluationCriterion(
                criterionID: "simulation-gate-status",
                channelID: "simulation-gate-status",
                comparator: .equal,
                target: .string(FlowGateStatus.passed.rawValue)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "simulation-waveform-variable-count",
                channelID: "simulation-waveform-variable-count",
                comparator: .greaterThan,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "simulation-tool-evidence",
                channelID: "simulation-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .number(1),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "simulation-calibration",
                channelID: "simulation-qualified-calibration",
                comparator: .equal,
                target: .bool(true),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "simulation-summary-artifact",
                channelID: "simulation-summary-artifact-present",
                comparator: .equal,
                target: .bool(true),
                metadata: ["artifactID": .string(artifactID)]
            ),
        ]
    }

    private func measurementCriteria(
        summary: SimulationRunSummaryReport
    ) -> [XcircuiteEvaluationCriterion] {
        summary.expectations.enumerated().map { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            return XcircuiteEvaluationCriterion(
                criterionID: "\(baseID)-within-tolerance",
                channelID: "\(baseID)-within-tolerance",
                comparator: .equal,
                target: .bool(true),
                tolerance: expectation.tolerance,
                metadata: [
                    "measurementName": .string(expectation.name),
                    "target": .number(expectation.target),
                ]
            )
        }
    }

    private func baseObservationChannels(
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        [
            XcircuiteObservationChannel(
                channelID: "simulation-summary-artifact-present",
                status: .observed,
                value: .bool(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "simulation-gate-status",
                status: .observed,
                value: .string(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: ["gateID": .string("simulation")]
            ),
            XcircuiteObservationChannel(
                channelID: "simulation-diagnostic-count",
                status: .observed,
                value: .number(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "simulation-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .number(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "simulation-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .bool(hasQualifiedEvidence),
                confidence: confidence
            ),
        ]
    }

    private func waveformObservationChannels(
        summary: SimulationRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        [
            XcircuiteObservationChannel(
                channelID: "simulation-waveform-variable-count",
                status: summary.waveformVariables.isEmpty ? .missing : .observed,
                value: .number(Double(summary.waveformVariables.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "simulation-waveform-variables",
                status: summary.waveformVariables.isEmpty ? .missing : .observed,
                value: .array(summary.waveformVariables.map { .string($0) }),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func measurementObservationChannels(
        summary: SimulationRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        let measurementsByName = Dictionary(
            summary.measurements.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return summary.expectations.enumerated().flatMap { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            let measurement = measurementsByName[expectation.name.lowercased()]
            let valueStatus: XcircuiteObservationChannelStatus = measurement == nil ? .missing : .observed
            let residualStatus: XcircuiteObservationChannelStatus = expectation.residual == nil ? .missing : .observed
            let withinStatus: XcircuiteObservationChannelStatus = expectation.status == "missing" ? .missing : .observed
            return [
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-value",
                    label: expectation.name,
                    status: valueStatus,
                    value: measurement.map { .number($0.value) },
                    unit: measurement?.unit,
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: [
                        "measurementName": .string(expectation.name),
                        "target": .number(expectation.target),
                    ]
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-residual",
                    label: "\(expectation.name) residual",
                    status: residualStatus,
                    value: expectation.residual.map { .number($0) },
                    unit: measurement?.unit,
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: [
                        "measurementName": .string(expectation.name),
                        "tolerance": .number(expectation.tolerance),
                    ]
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-within-tolerance",
                    label: "\(expectation.name) within tolerance",
                    status: withinStatus,
                    value: expectation.status == "missing" ? nil : .bool(expectation.status == "passed"),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: [
                        "measurementName": .string(expectation.name),
                        "target": .number(expectation.target),
                        "tolerance": .number(expectation.tolerance),
                    ]
                ),
            ]
        }
    }

    private func baseChannelResults(
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                criterionID: "simulation-gate-status",
                channelID: "simulation-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .string(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "simulation-summary-artifact",
                channelID: "simulation-summary-artifact-present",
                status: .accepted,
                observedValue: .bool(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                metadata: ["artifactID": .string(artifactID)]
            ),
        ]
    }

    private func waveformChannelResults(
        summary: SimulationRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                criterionID: "simulation-waveform-variable-count",
                channelID: "simulation-waveform-variable-count",
                status: summary.waveformVariables.isEmpty ? .inconclusive : .accepted,
                observedValue: .number(Double(summary.waveformVariables.count)),
                residual: summary.waveformVariables.isEmpty ? 1 : 0,
                likelihood: summary.waveformVariables.isEmpty ? 0 : 1,
                confidence: confidence
            ),
        ]
    }

    private func measurementChannelResults(
        summary: SimulationRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        summary.expectations.enumerated().map { index, expectation in
            let baseID = measurementChannelBase(index: index, name: expectation.name)
            return XcircuiteEvaluationChannelResult(
                criterionID: "\(baseID)-within-tolerance",
                channelID: "\(baseID)-within-tolerance",
                status: evaluationStatus(from: expectation.status),
                observedValue: expectation.status == "missing" ? nil : .bool(expectation.status == "passed"),
                residual: normalizedResidual(for: expectation),
                likelihood: likelihood(for: expectation),
                confidence: confidence,
                metadata: [
                    "measurementName": .string(expectation.name),
                    "target": .number(expectation.target),
                    "tolerance": .number(expectation.tolerance),
                ]
            )
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: SimulationRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        guard gateStatus != .passed else {
            return [
                XcircuiteFeedbackSignal(
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
                return XcircuiteFeedbackSignal(
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
                    confidence: confidence,
                    metadata: [
                        "measurementName": .string(expectation.name),
                        "target": .number(expectation.target),
                        "tolerance": .number(expectation.tolerance),
                    ]
                )
            }
    }

    private func dependencies(
        from artifacts: [ArtifactReference],
        excluding summaryArtifact: ArtifactReference
    ) -> [XcircuiteArtifactDependency] {
        artifacts
            .filter { $0.path != summaryArtifact.path }
            .map { artifact in
                XcircuiteArtifactDependency(
                    artifactID: artifact.artifactID,
                    path: artifact.path,
                    role: artifact.artifactID ?? artifact.kind.rawValue,
                    required: true
                )
            }
    }

    private func hasQualifiedEvidence(context: FlowExecutionContext, toolID: String) -> Bool {
        context.healthResults[toolID]?.evidence.contains { evidence in
            evidence.qualification?.qualified == true
        } == true
    }

    private func confidence(hasQualifiedEvidence: Bool) -> XcircuiteEvidenceConfidence {
        if hasQualifiedEvidence {
            return XcircuiteEvidenceConfidence(
                value: 0.8,
                posteriorVariance: 0.2,
                calibrationCoefficient: 0.7,
                calibrated: true
            )
        }
        return XcircuiteEvidenceConfidence(
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

    private func evaluationStatus(from status: String) -> XcircuiteEvaluationStatus {
        switch status {
        case "passed":
            .accepted
        case "failed":
            .rejected
        default:
            .inconclusive
        }
    }

    private func evaluationStatus(from status: FlowGateStatus) -> XcircuiteEvaluationStatus {
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

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> XcircuiteRunActionDiagnostic {
        XcircuiteRunActionDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionSeverity(
        _ severity: FlowDiagnosticSeverity
    ) -> XcircuiteRunActionDiagnosticSeverity {
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
