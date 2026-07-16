import CircuiteFoundation
import DesignFlowKernel
import Foundation

struct StageArtifactEnvelopeBuilder: Sendable {
    func summaryEnvelopeReference(
        summaryArtifactID: String,
        stageArtifacts: [ArtifactReference],
        domain: String,
        gateID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        guard let summaryArtifact = stageArtifacts.first(where: { $0.artifactID == summaryArtifactID }) else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: stageID)
        }

        return try await summaryEnvelopeReference(
            summaryArtifact: summaryArtifact,
            stageArtifacts: stageArtifacts,
            domain: domain,
            gateID: gateID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            stageID: stageID,
            toolID: toolID,
            context: context
        )
    }

    func summaryEnvelopeReference(
        summaryArtifact: ArtifactReference,
        stageArtifacts: [ArtifactReference],
        domain: String,
        gateID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        let artifactID = summaryArtifact.artifactID

        let envelope = FlowArtifactEnvelope(
            artifactID: artifactID,
            role: "\(domain)-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: FlowArtifactProducer(
                producerID: toolID,
                toolID: toolID
            ),
            dependencies: dependencies(
                from: stageArtifacts,
                excluding: summaryArtifact
            ),
            evaluationSpec: evaluationSpec(domain: domain, artifactID: artifactID),
            observationSet: observationSet(
                domain: domain,
                artifactID: artifactID,
                gateID: gateID,
                gateStatus: gateStatus,
                diagnostics: diagnostics,
                toolEvidenceCount: context.healthResults[toolID]?.evidence.count ?? 0,
                hasQualifiedEvidence: hasQualifiedEvidence(context: context, toolID: toolID)
            ),
            evaluationResult: evaluationResult(
                domain: domain,
                artifactID: artifactID,
                gateStatus: gateStatus,
                diagnostics: diagnostics,
                hasQualifiedEvidence: hasQualifiedEvidence(context: context, toolID: toolID)
            )
        )

        return try await context.persistArtifactEnvelope(envelope)
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

    private func evaluationSpec(domain: String, artifactID: String) -> FlowEvaluationSpec {
        FlowEvaluationSpec(
            specID: "\(artifactID)-evaluation-spec",
            objective: "Evaluate \(domain.uppercased()) summary evidence for stage readiness.",
            criteria: [
                FlowEvaluationCriterion(
                    criterionID: "\(domain)-gate-status",
                    channelID: "\(domain)-gate-status",
                    comparator: .equal,
                    target: .text(FlowGateStatus.passed.rawValue)
                ),
                FlowEvaluationCriterion(
                    criterionID: "\(domain)-tool-evidence",
                    channelID: "\(domain)-tool-evidence-count",
                    comparator: .greaterThanOrEqual,
                    target: .scalar(1),
                    required: false
                ),
                FlowEvaluationCriterion(
                    criterionID: "\(domain)-calibration",
                    channelID: "\(domain)-qualified-calibration",
                    comparator: .equal,
                    target: .boolean(true),
                    required: false
                ),
            ],
            requiredArtifactRoles: ["\(domain)-summary"],
            confidence: FlowEvidenceConfidence(
                value: 0.5,
                posteriorVariance: 0.5,
                calibrated: false
            )
        )
    }

    private func observationSet(
        domain: String,
        artifactID: String,
        gateID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool
    ) -> FlowObservationSet {
        FlowObservationSet(
            observationSetID: "\(artifactID)-observations",
            specID: "\(artifactID)-evaluation-spec",
            channels: [
                FlowObservationChannel(
                    channelID: "\(domain)-gate-status",
                    status: .observed,
                    value: .text(gateStatus.rawValue),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence),
                    context: FlowEvaluationContext(gateID: gateID)
                ),
                FlowObservationChannel(
                    channelID: "\(domain)-diagnostic-count",
                    status: .observed,
                    value: .scalar(Double(diagnostics.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
                ),
                FlowObservationChannel(
                    channelID: "\(domain)-tool-evidence-count",
                    status: toolEvidenceCount > 0 ? .observed : .missing,
                    value: .scalar(Double(toolEvidenceCount)),
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
                ),
                FlowObservationChannel(
                    channelID: "\(domain)-qualified-calibration",
                    status: hasQualifiedEvidence ? .observed : .uncalibrated,
                    value: .boolean(hasQualifiedEvidence),
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
                ),
            ],
            confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
        )
    }

    private func evaluationResult(
        domain: String,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        hasQualifiedEvidence: Bool
    ) -> FlowEvaluationResult {
        FlowEvaluationResult(
            evaluationID: "\(artifactID)-evaluation",
            specID: "\(artifactID)-evaluation-spec",
            status: evaluationStatus(from: gateStatus),
            likelihood: likelihood(from: gateStatus),
            residual: residual(from: gateStatus),
            confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence),
            channelResults: [
                FlowEvaluationChannelResult(
                    criterionID: "\(domain)-gate-status",
                    channelID: "\(domain)-gate-status",
                    status: evaluationStatus(from: gateStatus),
                    observedValue: .text(gateStatus.rawValue),
                    residual: residual(from: gateStatus),
                    likelihood: likelihood(from: gateStatus),
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence),
                    diagnostics: diagnostics.map(runActionDiagnostic)
                ),
            ],
            feedbackSignals: feedbackSignals(
                domain: domain,
                artifactID: artifactID,
                gateStatus: gateStatus,
                hasQualifiedEvidence: hasQualifiedEvidence
            ),
            summary: summary(domain: domain, gateStatus: gateStatus)
        )
    }

    private func feedbackSignals(
        domain: String,
        artifactID: String,
        gateStatus: FlowGateStatus,
        hasQualifiedEvidence: Bool
    ) -> [FlowFeedbackSignal] {
        switch gateStatus {
        case .passed, .waived:
            return [
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-continue",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "\(domain)-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "\(domain.uppercased()) summary is usable as downstream evidence.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["continue-flow"],
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
                ),
            ]
        case .failed, .incomplete, .blocked:
            return [
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-repair-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "\(domain)-gate-status",
                    routingLevel: .structureMapping,
                    severity: gateStatus == .failed || gateStatus == .blocked ? .error : .warning,
                    summary: "\(domain.uppercased()) residual should be inspected before planning repair.",
                    residual: residual(from: gateStatus),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-\(domain)-summary", "generate-planning-problem"],
                    confidence: confidence(hasQualifiedEvidence: hasQualifiedEvidence)
                ),
            ]
        }
    }

    private func hasQualifiedEvidence(context: FlowExecutionContext, toolID: String) -> Bool {
        context.healthResults[toolID]?.evidence.contains(where: { evidence in
            (evidence.kind == .corpus || evidence.kind == .oracle)
                && evidence.hasVerifiableArtifactBinding
        }) == true
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

    private func residual(from status: FlowGateStatus) -> Double {
        switch status {
        case .passed, .waived:
            0
        case .incomplete:
            0.5
        case .failed:
            1
        case .blocked:
            1
        }
    }

    private func summary(domain: String, gateStatus: FlowGateStatus) -> String {
        "\(domain.uppercased()) summary evaluation ended with gate status \(gateStatus.rawValue)."
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
}
