import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PEXEngine

struct PEXSummaryEnvelopeBuilder: Sendable {
    private struct AggregateMetrics: Sendable, Hashable {
        let successfulCornerCount: Int
        let failedCornerCount: Int
        let netCount: Int
        let elementCount: Int
        let totalGroundCapF: Double
        let totalCouplingCapF: Double
        let totalCapacitanceF: Double
        let totalResistanceOhm: Double
        let summaryDiagnosticCount: Int
        let summaryErrorDiagnosticCount: Int
    }

    func envelopeReference(
        summary: PEXRunSummaryReport,
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
        let artifactID = summaryArtifact.artifactID

        let hasQualifiedEvidence = hasQualifiedEvidence(context: context, toolID: toolID)
        let toolEvidenceCount = context.healthResults[toolID]?.evidence.count ?? 0
        let confidence = confidence(hasQualifiedEvidence: hasQualifiedEvidence)
        let aggregate = aggregateMetrics(summary: summary)
        let criteria = baseCriteria(artifactID: artifactID) + cornerCriteria(summary: summary)
        let channels = baseObservationChannels(
            summary: summary,
            aggregate: aggregate,
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            toolEvidenceCount: toolEvidenceCount,
            hasQualifiedEvidence: hasQualifiedEvidence,
            confidence: confidence
        ) + cornerObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        ) + multiCornerObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        ) + topNetObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        ) + multiCornerTopNetObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        )
        let channelResults = baseChannelResults(
            summary: summary,
            aggregate: aggregate,
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            confidence: confidence
        ) + multiCornerChannelResults(
            summary: summary,
            confidence: confidence
        ) + cornerChannelResults(summary: summary, confidence: confidence)

        let envelope = FlowArtifactEnvelope(
            artifactID: artifactID,
            role: "pex-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: FlowArtifactProducer(producerID: toolID, toolID: toolID),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: FlowEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate PEX parasitic evidence for stage readiness and post-layout planning.",
                criteria: criteria,
                requiredArtifactRoles: ["pex-summary", "parasitic"],
                confidence: FlowEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false)
            ),
            observationSet: FlowObservationSet(
                observationSetID: "\(artifactID)-observations",
                specID: "\(artifactID)-evaluation-spec",
                channels: channels,
                confidence: confidence
            ),
            evaluationResult: FlowEvaluationResult(
                evaluationID: "\(artifactID)-evaluation",
                specID: "\(artifactID)-evaluation-spec",
                status: evaluationStatus(summary: summary, aggregate: aggregate, gateStatus: gateStatus),
                likelihood: likelihood(summary: summary, aggregate: aggregate, gateStatus: gateStatus),
                residual: residual(summary: summary, aggregate: aggregate, gateStatus: gateStatus),
                confidence: confidence,
                channelResults: channelResults,
                feedbackSignals: feedbackSignals(
                    artifactID: artifactID,
                    summary: summary,
                    aggregate: aggregate,
                    gateStatus: gateStatus,
                    confidence: confidence
                ),
                summary: "PEX summary evaluation ended with gate status \(gateStatus.rawValue)."
            )
        )

        return try await context.persistArtifactEnvelope(envelope)
    }

    private func baseCriteria(artifactID: String) -> [FlowEvaluationCriterion] {
        [
            FlowEvaluationCriterion(
                criterionID: "pex-gate-status",
                channelID: "pex-gate-status",
                comparator: .equal,
                target: .text(FlowGateStatus.passed.rawValue)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-artifact-completeness-status",
                channelID: "pex-artifact-completeness-status",
                comparator: .equal,
                target: .text(PEXArtifactCompletenessStatus.complete.rawValue)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-failed-corner-count",
                channelID: "pex-failed-corner-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-multi-corner-failed-corner-count",
                channelID: "pex-multi-corner-failed-corner-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-summary-error-diagnostic-count",
                channelID: "pex-summary-error-diagnostic-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-multi-corner-error-diagnostic-count",
                channelID: "pex-multi-corner-error-diagnostic-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-multi-corner-shared-technology",
                channelID: "pex-multi-corner-comparison-basis",
                comparator: .equal,
                target: .text(PEXExtractorMultiCornerComparisonBasis.sharedTechnology.rawValue),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-tool-evidence",
                channelID: "pex-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .scalar(1),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-calibration",
                channelID: "pex-qualified-calibration",
                comparator: .equal,
                target: .boolean(true),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "pex-summary-artifact",
                channelID: "pex-summary-artifact-present",
                comparator: .equal,
                target: .boolean(true),
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
        ]
    }

    private func cornerCriteria(summary: PEXRunSummaryReport) -> [FlowEvaluationCriterion] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            return [
                FlowEvaluationCriterion(
                    criterionID: "\(baseID)-status",
                    channelID: "\(baseID)-status",
                    comparator: .equal,
                    target: .text(PEXRunStatus.success.rawValue)
                ),
                FlowEvaluationCriterion(
                    criterionID: "\(baseID)-parasitic-ir-present",
                    channelID: "\(baseID)-parasitic-ir-present",
                    comparator: .equal,
                    target: .boolean(true)
                ),
            ]
        }
    }

    private func baseObservationChannels(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        [
            FlowObservationChannel(
                channelID: "pex-summary-artifact-present",
                status: .observed,
                value: .boolean(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-gate-status",
                status: .observed,
                value: .text(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                context: FlowEvaluationContext(gateID: "pex")
            ),
            FlowObservationChannel(
                channelID: "pex-run-status",
                status: .observed,
                value: .text(summary.summary.status),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-artifact-completeness-status",
                status: .observed,
                value: .text(summary.completeness.status.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-diagnostic-count",
                status: .observed,
                value: .scalar(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .scalar(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .boolean(hasQualifiedEvidence),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-corner-count",
                status: .observed,
                value: .scalar(Double(summary.summary.corners.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-successful-corner-count",
                status: .observed,
                value: .scalar(Double(aggregate.successfulCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-failed-corner-count",
                status: .observed,
                value: .scalar(Double(aggregate.failedCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-net-count",
                status: .observed,
                value: .scalar(Double(aggregate.netCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-element-count",
                status: .observed,
                value: .scalar(Double(aggregate.elementCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-ground-capacitance-f",
                status: .observed,
                value: .scalar(aggregate.totalGroundCapF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-coupling-capacitance-f",
                status: .observed,
                value: .scalar(aggregate.totalCouplingCapF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-capacitance-f",
                status: .observed,
                value: .scalar(aggregate.totalCapacitanceF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-total-resistance-ohm",
                status: .observed,
                value: .scalar(aggregate.totalResistanceOhm),
                unit: "ohm",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-artifact-issue-count",
                status: .observed,
                value: .scalar(Double(summary.completeness.issues.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-missing-artifact-issue-count",
                status: .observed,
                value: .scalar(Double(issueCount(summary: summary, kind: .missingArtifact))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-missing-ir-issue-count",
                status: .observed,
                value: .scalar(Double(issueCount(summary: summary, kind: .missingIR))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-summary-diagnostic-count",
                status: .observed,
                value: .scalar(Double(aggregate.summaryDiagnosticCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-summary-error-diagnostic-count",
                status: .observed,
                value: .scalar(Double(aggregate.summaryErrorDiagnosticCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func cornerObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            return [
                FlowObservationChannel(
                    channelID: "\(baseID)-status",
                    label: "PEX corner \(corner.cornerID)",
                    status: .observed,
                    value: .text(corner.status),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-net-count",
                    status: .observed,
                    value: .scalar(Double(corner.netCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-element-count",
                    status: .observed,
                    value: .scalar(Double(corner.elementCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-total-ground-capacitance-f",
                    status: .observed,
                    value: .scalar(corner.totalGroundCapF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-total-coupling-capacitance-f",
                    status: .observed,
                    value: .scalar(corner.totalCouplingCapF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-total-capacitance-f",
                    status: .observed,
                    value: .scalar(corner.totalCapacitanceF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-total-resistance-ohm",
                    status: .observed,
                    value: .scalar(corner.totalResistanceOhm),
                    unit: "ohm",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-raw-output-artifact-count",
                    status: .observed,
                    value: .scalar(Double(corner.rawOutputArtifactIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-parasitic-ir-present",
                    status: corner.parasiticIRArtifactID == nil ? .missing : .observed,
                    value: .boolean(corner.parasiticIRArtifactID != nil),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-spef-roundtrip-present",
                    status: corner.spefRoundTripArtifactID == nil ? .missing : .observed,
                    value: .boolean(corner.spefRoundTripArtifactID != nil),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-top-net-count",
                    status: corner.topNets.isEmpty ? .missing : .observed,
                    value: .scalar(Double(corner.topNets.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-diagnostic-count",
                    status: .observed,
                    value: .scalar(Double(corner.diagnostics.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
            ]
        }
    }

    private func multiCornerObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        let multiCorner = summary.summary.multiCorner
        return [
            FlowObservationChannel(
                channelID: "pex-multi-corner-successful-corner-count",
                status: .derived,
                value: .scalar(Double(multiCorner.successfulCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-comparison-basis",
                status: .derived,
                value: .text(multiCorner.comparisonBasis.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-failed-corner-count",
                status: .derived,
                value: .scalar(Double(multiCorner.failedCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-worst-capacitance-corner-id",
                status: multiCorner.worstCapacitanceCornerID == nil ? .missing : .derived,
                value: optionalStringValue(multiCorner.worstCapacitanceCornerID),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-total-capacitance-spread-f",
                status: .derived,
                value: .scalar(multiCorner.totalCapacitance.spread),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-total-capacitance-relative-spread",
                status: multiCorner.totalCapacitance.relativeSpread == nil ? .missing : .derived,
                value: optionalNumberValue(multiCorner.totalCapacitance.relativeSpread),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-worst-resistance-corner-id",
                status: multiCorner.worstResistanceCornerID == nil ? .missing : .derived,
                value: optionalStringValue(multiCorner.worstResistanceCornerID),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-total-resistance-spread-ohm",
                status: .derived,
                value: .scalar(multiCorner.totalResistance.spread),
                unit: "ohm",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-total-resistance-relative-spread",
                status: multiCorner.totalResistance.relativeSpread == nil ? .missing : .derived,
                value: optionalNumberValue(multiCorner.totalResistance.relativeSpread),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-diagnostic-count",
                status: .derived,
                value: .scalar(Double(multiCorner.diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "pex-multi-corner-error-diagnostic-count",
                status: .derived,
                value: .scalar(Double(multiCornerErrorDiagnosticCount(summary))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func topNetObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        summary.summary.corners.enumerated().flatMap { cornerIndex, corner in
            corner.topNets.enumerated().flatMap { netIndex, net in
                let baseID = topNetChannelBase(cornerIndex: cornerIndex, corner: corner, netIndex: netIndex, net: net)
                return [
                    FlowObservationChannel(
                        channelID: "\(baseID)-total-capacitance-f",
                        label: "PEX top net \(net.name)",
                        status: .observed,
                        value: .scalar(net.groundCapF + net.couplingCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence
                    ),
                    FlowObservationChannel(
                        channelID: "\(baseID)-ground-capacitance-f",
                        status: .observed,
                        value: .scalar(net.groundCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence
                    ),
                    FlowObservationChannel(
                        channelID: "\(baseID)-coupling-capacitance-f",
                        status: .observed,
                        value: .scalar(net.couplingCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence
                    ),
                    FlowObservationChannel(
                        channelID: "\(baseID)-resistance-ohm",
                        status: .observed,
                        value: .scalar(net.resistanceOhm),
                        unit: "ohm",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence
                    ),
                    FlowObservationChannel(
                        channelID: "\(baseID)-node-count",
                        status: .observed,
                        value: .scalar(Double(net.nodeCount)),
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence
                    ),
                ]
            }
        }
    }

    private func multiCornerTopNetObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        summary.summary.multiCorner.topNetSpreads.enumerated().flatMap { index, spread in
            let baseID = multiCornerNetSpreadChannelBase(index: index, spread: spread)
            return [
                FlowObservationChannel(
                    channelID: "\(baseID)-total-capacitance-spread-f",
                    label: "PEX multi-corner net \(spread.netName)",
                    status: .derived,
                    value: .scalar(spread.totalCapacitance.spread),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-total-capacitance-relative-spread",
                    status: spread.totalCapacitance.relativeSpread == nil ? .missing : .derived,
                    value: optionalNumberValue(spread.totalCapacitance.relativeSpread),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-resistance-spread-ohm",
                    status: .derived,
                    value: .scalar(spread.resistance.spread),
                    unit: "ohm",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-observed-corner-count",
                    status: .derived,
                    value: .scalar(Double(spread.observedCornerIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
            ]
        }
    }

    private func baseChannelResults(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                criterionID: "pex-gate-status",
                channelID: "pex-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .text(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-summary-artifact",
                channelID: "pex-summary-artifact-present",
                status: .accepted,
                observedValue: .boolean(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-artifact-completeness-status",
                channelID: "pex-artifact-completeness-status",
                status: completenessStatus(summary.completeness.status),
                observedValue: .text(summary.completeness.status.rawValue),
                residual: summary.completeness.status == .complete ? 0 : Double(summary.completeness.issues.count),
                likelihood: summary.completeness.status == .complete ? 1 : 0,
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-failed-corner-count",
                channelID: "pex-failed-corner-count",
                status: countStatus(aggregate.failedCornerCount),
                observedValue: .scalar(Double(aggregate.failedCornerCount)),
                residual: Double(aggregate.failedCornerCount),
                likelihood: countLikelihood(aggregate.failedCornerCount),
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-summary-error-diagnostic-count",
                channelID: "pex-summary-error-diagnostic-count",
                status: countStatus(aggregate.summaryErrorDiagnosticCount),
                observedValue: .scalar(Double(aggregate.summaryErrorDiagnosticCount)),
                residual: Double(aggregate.summaryErrorDiagnosticCount),
                likelihood: countLikelihood(aggregate.summaryErrorDiagnosticCount),
                confidence: confidence
            ),
        ]
    }

    private func multiCornerChannelResults(
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        let multiCorner = summary.summary.multiCorner
        let errorDiagnosticCount = multiCornerErrorDiagnosticCount(summary)
        let sharedTechnology = multiCorner.comparisonBasis == .sharedTechnology
        return [
            FlowEvaluationChannelResult(
                criterionID: "pex-multi-corner-shared-technology",
                channelID: "pex-multi-corner-comparison-basis",
                status: sharedTechnology ? .accepted : .rejected,
                observedValue: .text(multiCorner.comparisonBasis.rawValue),
                residual: sharedTechnology ? 0 : 1,
                likelihood: sharedTechnology ? 1 : 0,
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-multi-corner-failed-corner-count",
                channelID: "pex-multi-corner-failed-corner-count",
                status: countStatus(multiCorner.failedCornerCount),
                observedValue: .scalar(Double(multiCorner.failedCornerCount)),
                residual: Double(multiCorner.failedCornerCount),
                likelihood: countLikelihood(multiCorner.failedCornerCount),
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "pex-multi-corner-error-diagnostic-count",
                channelID: "pex-multi-corner-error-diagnostic-count",
                status: countStatus(errorDiagnosticCount),
                observedValue: .scalar(Double(errorDiagnosticCount)),
                residual: Double(errorDiagnosticCount),
                likelihood: countLikelihood(errorDiagnosticCount),
                confidence: confidence,
                diagnostics: multiCorner.diagnostics.map(runActionDiagnostic)
            ),
        ]
    }

    private func cornerChannelResults(
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            let hasIR = corner.parasiticIRArtifactID != nil
            return [
                FlowEvaluationChannelResult(
                    criterionID: "\(baseID)-status",
                    channelID: "\(baseID)-status",
                    status: cornerEvaluationStatus(corner.status),
                    observedValue: .text(corner.status),
                    residual: corner.status == PEXRunStatus.success.rawValue ? 0 : 1,
                    likelihood: corner.status == PEXRunStatus.success.rawValue ? 1 : 0,
                    confidence: confidence,
                    diagnostics: corner.diagnostics.map(runActionDiagnostic)
                ),
                FlowEvaluationChannelResult(
                    criterionID: "\(baseID)-parasitic-ir-present",
                    channelID: "\(baseID)-parasitic-ir-present",
                    status: hasIR ? .accepted : .rejected,
                    observedValue: .boolean(hasIR),
                    residual: hasIR ? 0 : 1,
                    likelihood: hasIR ? 1 : 0,
                    confidence: confidence
                ),
            ]
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        var signals: [FlowFeedbackSignal] = []

        if gateStatus == .passed
            && summary.completeness.status == .complete
            && aggregate.failedCornerCount == 0
            && aggregate.summaryErrorDiagnosticCount == 0 {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-continue",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX summary is usable as downstream post-layout evidence.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["continue-flow", "compare-post-layout-metrics"],
                    confidence: confidence
                )
            )
        }

        if summary.completeness.status != .complete || !summary.completeness.issues.isEmpty {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-artifact-completeness",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-artifact-completeness-status",
                    routingLevel: .structureMapping,
                    severity: summary.completeness.status == .invalid ? .error : .warning,
                    summary: "PEX artifacts are not complete enough for reliable post-layout planning.",
                    residual: Double(summary.completeness.issues.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-manifest", "repair-pex-artifact-production"],
                    confidence: confidence
                )
            )
        }

        signals.append(contentsOf: failedCornerSignals(
            artifactID: artifactID,
            summary: summary,
            confidence: confidence
        ))
        signals.append(contentsOf: comparisonBasisSignals(
            artifactID: artifactID,
            summary: summary,
            confidence: confidence
        ))
        signals.append(contentsOf: multiCornerSpreadSignals(
            artifactID: artifactID,
            summary: summary,
            confidence: confidence
        ))
        signals.append(contentsOf: dominantNetSignals(
            artifactID: artifactID,
            summary: summary,
            confidence: confidence
        ))

        if gateStatus != .passed && signals.isEmpty {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-repair-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-gate-status",
                    routingLevel: .structureMapping,
                    severity: gateStatus == .failed ? .error : .warning,
                    summary: "PEX summary did not provide enough structured detail for localized repair.",
                    residual: residual(summary: summary, aggregate: aggregate, gateStatus: gateStatus),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary", "inspect-pex-run-log"],
                    confidence: confidence
                )
            )
        }

        if signals.isEmpty {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-review-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX summary has no active repair feedback.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary"],
                    confidence: confidence
                )
            )
        }

        return signals
    }

    private func comparisonBasisSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        switch summary.summary.multiCorner.comparisonBasis {
        case .sharedTechnology:
            return []
        case .perCornerTechnology:
            return [
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-process-specific-comparison",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-comparison-basis",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "PEX corner spread is process-specific; foundry correlation evidence is required before PVT signoff promotion.",
                    residual: 1,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary", "compare-post-layout-metrics"],
                    confidence: confidence
                ),
            ]
        case .unknown:
            return [
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-unknown-comparison-basis",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-comparison-basis",
                    routingLevel: .structureMapping,
                    severity: .warning,
                    summary: "PEX comparison basis is unknown; do not promote the retained spread to a PVT signoff claim.",
                    residual: 1,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary"],
                    confidence: confidence
                ),
            ]
        }
    }

    private func failedCornerSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        summary.summary.corners.enumerated().compactMap { index, corner in
            guard corner.status != PEXRunStatus.success.rawValue || !corner.diagnostics.isEmpty else {
                return nil
            }
            let baseID = cornerChannelBase(index: index, corner: corner)
            return FlowFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-status",
                routingLevel: .structureMapping,
                severity: corner.status == PEXRunStatus.partialSuccess.rawValue ? .warning : .error,
                summary: "PEX corner \(corner.cornerID) ended with status \(corner.status).",
                residual: corner.status == PEXRunStatus.success.rawValue ? 0 : 1,
                affectedArtifactIDs: [artifactID],
                suggestedActions: ["inspect-pex-corner", "repair-pex-extraction-inputs"],
                confidence: confidence
            )
        }
    }

    private func multiCornerSpreadSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        let multiCorner = summary.summary.multiCorner
        guard multiCorner.successfulCornerCount > 1 else {
            return []
        }

        var signals: [FlowFeedbackSignal] = []
        if multiCorner.totalCapacitance.spread > 0,
           let cornerID = multiCorner.worstCapacitanceCornerID {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-capacitance-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-total-capacitance-spread-f",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX corner \(cornerID) has the highest total capacitance across retained corners.",
                    residual: multiCorner.totalCapacitance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-worst-pex-corner", "compare-post-layout-metrics"],
                    confidence: confidence
                )
            )
        }
        if multiCorner.totalResistance.spread > 0,
           let cornerID = multiCorner.worstResistanceCornerID {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-resistance-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-total-resistance-spread-ohm",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX corner \(cornerID) has the highest total resistance across retained corners.",
                    residual: multiCorner.totalResistance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-worst-pex-corner", "compare-post-layout-metrics"],
                    confidence: confidence
                )
            )
        }
        if let spread = multiCorner.topNetSpreads.first, spread.totalCapacitance.spread > 0 {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-net-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "\(multiCornerNetSpreadChannelBase(index: 0, spread: spread))-total-capacitance-spread-f",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX net \(spread.netName) has the largest retained corner capacitance spread.",
                    residual: spread.totalCapacitance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-parasitic-net-spread", "compare-post-layout-metrics"],
                    confidence: confidence
                )
            )
        }

        return signals
    }

    private func dominantNetSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        summary.summary.corners.enumerated().compactMap { cornerIndex, corner in
            guard let net = corner.topNets.first else {
                return nil
            }
            let channelBase = topNetChannelBase(cornerIndex: cornerIndex, corner: corner, netIndex: 0, net: net)
            return FlowFeedbackSignal(
                signalID: "\(channelBase)-post-layout-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(channelBase)-total-capacitance-f",
                routingLevel: .localSurface,
                severity: .info,
                summary: "PEX corner \(corner.cornerID) is dominated by net \(net.name) by capacitance.",
                affectedArtifactIDs: [artifactID],
                suggestedActions: ["inspect-dominant-parasitic-net", "compare-post-layout-metrics"],
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
        return descriptor.trustProfile.evidence.contains { $0.hasVerifiableArtifactBinding }
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

    private func evaluationStatus(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus
    ) -> FlowEvaluationStatus {
        if gateStatus == .incomplete || summary.completeness.status == .incomplete {
            return .inconclusive
        }
        if gateStatus == .failed
            || summary.completeness.status == .invalid
            || aggregate.failedCornerCount > 0
            || aggregate.summaryErrorDiagnosticCount > 0 {
            return .rejected
        }
        return .accepted
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

    private func completenessStatus(
        _ status: PEXArtifactCompletenessStatus
    ) -> FlowEvaluationStatus {
        switch status {
        case .complete:
            .accepted
        case .incomplete:
            .inconclusive
        case .invalid:
            .rejected
        }
    }

    private func cornerEvaluationStatus(_ status: String) -> FlowEvaluationStatus {
        switch status {
        case PEXRunStatus.success.rawValue:
            .accepted
        case PEXRunStatus.partialSuccess.rawValue:
            .inconclusive
        default:
            .rejected
        }
    }

    private func countStatus(_ count: Int) -> FlowEvaluationStatus {
        count == 0 ? .accepted : .rejected
    }

    private func likelihood(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus
    ) -> Double {
        if aggregate.failedCornerCount > 0
            || aggregate.summaryErrorDiagnosticCount > 0
            || summary.completeness.status == .invalid {
            return 0
        }
        return likelihood(from: gateStatus)
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

    private func countLikelihood(_ count: Int) -> Double {
        count == 0 ? 1 : 0
    }

    private func residual(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus
    ) -> Double {
        if aggregate.failedCornerCount > 0 {
            return Double(aggregate.failedCornerCount)
        }
        if aggregate.summaryErrorDiagnosticCount > 0 {
            return Double(aggregate.summaryErrorDiagnosticCount)
        }
        if !summary.completeness.issues.isEmpty {
            return Double(summary.completeness.issues.count)
        }
        switch gateStatus {
        case .passed, .waived:
            return 0
        case .incomplete:
            return 0.5
        case .failed:
            return 1
        case .blocked:
            return 1
        }
    }

    private func aggregateMetrics(summary: PEXRunSummaryReport) -> AggregateMetrics {
        let corners = summary.summary.corners
        return AggregateMetrics(
            successfulCornerCount: corners.filter { $0.status == PEXRunStatus.success.rawValue }.count,
            failedCornerCount: corners.filter { $0.status != PEXRunStatus.success.rawValue }.count,
            netCount: corners.reduce(0) { $0 + $1.netCount },
            elementCount: corners.reduce(0) { $0 + $1.elementCount },
            totalGroundCapF: corners.reduce(0) { $0 + $1.totalGroundCapF },
            totalCouplingCapF: corners.reduce(0) { $0 + $1.totalCouplingCapF },
            totalCapacitanceF: corners.reduce(0) { $0 + $1.totalCapacitanceF },
            totalResistanceOhm: corners.reduce(0) { $0 + $1.totalResistanceOhm },
            summaryDiagnosticCount: corners.reduce(0) { $0 + $1.diagnostics.count },
            summaryErrorDiagnosticCount: corners.reduce(0) { partial, corner in
                partial + corner.diagnostics.filter { $0.severity == "error" }.count
            }
        )
    }

    private func issueCount(
        summary: PEXRunSummaryReport,
        kind: PEXArtifactCompletenessIssueKind
    ) -> Int {
        summary.completeness.issues.filter { $0.kind == kind }.count
    }

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> FlowRunDiagnostic {
        FlowRunDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionDiagnostic(_ diagnostic: PEXRunSummaryDiagnostic) -> FlowRunDiagnostic {
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

    private func runActionSeverity(_ severity: String) -> FlowRunDiagnosticSeverity {
        switch severity {
        case "error":
            .error
        case "warning":
            .warning
        default:
            .info
        }
    }

    private func cornerChannelBase(index: Int, corner: PEXCornerParasiticSummary) -> String {
        "pex-corner-\(index)-\(slug(corner.cornerID))"
    }

    private func topNetChannelBase(
        cornerIndex: Int,
        corner: PEXCornerParasiticSummary,
        netIndex: Int,
        net: PEXNetParasiticSummary
    ) -> String {
        "\(cornerChannelBase(index: cornerIndex, corner: corner))-top-net-\(netIndex)-\(slug(net.name))"
    }

    private func multiCornerNetSpreadChannelBase(index: Int, spread: PEXNetCornerSpreadSummary) -> String {
        "pex-multi-corner-net-\(index)-\(slug(spread.netName))"
    }

    private func optionalStringValue(_ value: String?) -> FlowMetricValue? {
        value.map(FlowMetricValue.text)
    }

    private func optionalNumberValue(_ value: Double?) -> FlowMetricValue? {
        value.map(FlowMetricValue.scalar)
    }

    private func multiCornerErrorDiagnosticCount(_ summary: PEXRunSummaryReport) -> Int {
        summary.summary.multiCorner.diagnostics.filter { $0.severity == "error" }.count
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
        return compact.isEmpty ? "value" : compact
    }
}
