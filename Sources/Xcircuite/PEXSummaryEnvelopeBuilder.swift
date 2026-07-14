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
    ) throws -> ArtifactReference {
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

        let envelope = XcircuiteArtifactEnvelope(
            artifactID: artifactID,
            role: "pex-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: XcircuiteArtifactProducer(producerID: toolID, toolID: toolID),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: XcircuiteEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate PEX parasitic evidence for stage readiness and post-layout planning.",
                criteria: criteria,
                requiredArtifactRoles: ["pex-summary", "parasitic"],
                confidence: XcircuiteEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false),
                metadata: [
                    "backendID": .string(summary.summary.backendID),
                    "runStatus": .string(summary.summary.status),
                    "cornerCount": .number(Double(summary.summary.corners.count)),
                    "multiCornerComparisonBasis": .string(summary.summary.multiCorner.comparisonBasis.rawValue),
                    "totalNetCount": .number(Double(aggregate.netCount)),
                    "totalElementCount": .number(Double(aggregate.elementCount)),
                ]
            ),
            observationSet: XcircuiteObservationSet(
                observationSetID: "\(artifactID)-observations",
                specID: "\(artifactID)-evaluation-spec",
                channels: channels,
                confidence: confidence,
                metadata: [
                    "backendID": .string(summary.summary.backendID),
                    "runID": .string(summary.summary.runID),
                    "runStatus": .string(summary.summary.status),
                    "multiCornerComparisonBasis": .string(summary.summary.multiCorner.comparisonBasis.rawValue),
                    "completenessStatus": .string(summary.completeness.status.rawValue),
                ]
            ),
            evaluationResult: XcircuiteEvaluationResult(
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
                summary: "PEX summary evaluation ended with gate status \(gateStatus.rawValue).",
                metadata: [
                    "failedCornerCount": .number(Double(aggregate.failedCornerCount)),
                    "artifactIssueCount": .number(Double(summary.completeness.issues.count)),
                    "summaryErrorDiagnosticCount": .number(Double(aggregate.summaryErrorDiagnosticCount)),
                    "totalCapacitanceF": .number(aggregate.totalCapacitanceF),
                    "totalResistanceOhm": .number(aggregate.totalResistanceOhm),
                ]
            ),
            metadata: [
                "gateID": .string("pex"),
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
                criterionID: "pex-gate-status",
                channelID: "pex-gate-status",
                comparator: .equal,
                target: .string(FlowGateStatus.passed.rawValue)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-artifact-completeness-status",
                channelID: "pex-artifact-completeness-status",
                comparator: .equal,
                target: .string(PEXArtifactCompletenessStatus.complete.rawValue)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-failed-corner-count",
                channelID: "pex-failed-corner-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-multi-corner-failed-corner-count",
                channelID: "pex-multi-corner-failed-corner-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-summary-error-diagnostic-count",
                channelID: "pex-summary-error-diagnostic-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-multi-corner-error-diagnostic-count",
                channelID: "pex-multi-corner-error-diagnostic-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-multi-corner-shared-technology",
                channelID: "pex-multi-corner-comparison-basis",
                comparator: .equal,
                target: .string(PEXExtractorMultiCornerComparisonBasis.sharedTechnology.rawValue),
                required: false,
                metadata: [
                    "interpretation": .string(
                        "Optional technology-scope signal; every PVT promotion still requires foundry correlation evidence."
                    ),
                ]
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-tool-evidence",
                channelID: "pex-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .number(1),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-calibration",
                channelID: "pex-qualified-calibration",
                comparator: .equal,
                target: .bool(true),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "pex-summary-artifact",
                channelID: "pex-summary-artifact-present",
                comparator: .equal,
                target: .bool(true),
                metadata: ["artifactID": .string(artifactID)]
            ),
        ]
    }

    private func cornerCriteria(summary: PEXRunSummaryReport) -> [XcircuiteEvaluationCriterion] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            return [
                XcircuiteEvaluationCriterion(
                    criterionID: "\(baseID)-status",
                    channelID: "\(baseID)-status",
                    comparator: .equal,
                    target: .string(PEXRunStatus.success.rawValue),
                    metadata: cornerMetadata(index: index, corner: corner)
                ),
                XcircuiteEvaluationCriterion(
                    criterionID: "\(baseID)-parasitic-ir-present",
                    channelID: "\(baseID)-parasitic-ir-present",
                    comparator: .equal,
                    target: .bool(true),
                    metadata: cornerMetadata(index: index, corner: corner)
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
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        [
            XcircuiteObservationChannel(
                channelID: "pex-summary-artifact-present",
                status: .observed,
                value: .bool(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-gate-status",
                status: .observed,
                value: .string(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: ["gateID": .string("pex")]
            ),
            XcircuiteObservationChannel(
                channelID: "pex-run-status",
                status: .observed,
                value: .string(summary.summary.status),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-artifact-completeness-status",
                status: .observed,
                value: .string(summary.completeness.status.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-diagnostic-count",
                status: .observed,
                value: .number(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .number(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .bool(hasQualifiedEvidence),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-corner-count",
                status: .observed,
                value: .number(Double(summary.summary.corners.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-successful-corner-count",
                status: .observed,
                value: .number(Double(aggregate.successfulCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-failed-corner-count",
                status: .observed,
                value: .number(Double(aggregate.failedCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-net-count",
                status: .observed,
                value: .number(Double(aggregate.netCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-element-count",
                status: .observed,
                value: .number(Double(aggregate.elementCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-ground-capacitance-f",
                status: .observed,
                value: .number(aggregate.totalGroundCapF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-coupling-capacitance-f",
                status: .observed,
                value: .number(aggregate.totalCouplingCapF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-capacitance-f",
                status: .observed,
                value: .number(aggregate.totalCapacitanceF),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-total-resistance-ohm",
                status: .observed,
                value: .number(aggregate.totalResistanceOhm),
                unit: "ohm",
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-artifact-issue-count",
                status: .observed,
                value: .number(Double(summary.completeness.issues.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-missing-artifact-issue-count",
                status: .observed,
                value: .number(Double(issueCount(summary: summary, kind: .missingArtifact))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-missing-ir-issue-count",
                status: .observed,
                value: .number(Double(issueCount(summary: summary, kind: .missingIR))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-summary-diagnostic-count",
                status: .observed,
                value: .number(Double(aggregate.summaryDiagnosticCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-summary-error-diagnostic-count",
                status: .observed,
                value: .number(Double(aggregate.summaryErrorDiagnosticCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func cornerObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            let metadata = cornerMetadata(index: index, corner: corner)
            return [
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-status",
                    label: "PEX corner \(corner.cornerID)",
                    status: .observed,
                    value: .string(corner.status),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-net-count",
                    status: .observed,
                    value: .number(Double(corner.netCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-element-count",
                    status: .observed,
                    value: .number(Double(corner.elementCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-ground-capacitance-f",
                    status: .observed,
                    value: .number(corner.totalGroundCapF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-coupling-capacitance-f",
                    status: .observed,
                    value: .number(corner.totalCouplingCapF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-capacitance-f",
                    status: .observed,
                    value: .number(corner.totalCapacitanceF),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-resistance-ohm",
                    status: .observed,
                    value: .number(corner.totalResistanceOhm),
                    unit: "ohm",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-raw-output-artifact-count",
                    status: .observed,
                    value: .number(Double(corner.rawOutputArtifactIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-parasitic-ir-present",
                    status: corner.parasiticIRArtifactID == nil ? .missing : .observed,
                    value: .bool(corner.parasiticIRArtifactID != nil),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-spef-roundtrip-present",
                    status: corner.spefRoundTripArtifactID == nil ? .missing : .observed,
                    value: .bool(corner.spefRoundTripArtifactID != nil),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-top-net-count",
                    status: corner.topNets.isEmpty ? .missing : .observed,
                    value: .number(Double(corner.topNets.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-diagnostic-count",
                    status: .observed,
                    value: .number(Double(corner.diagnostics.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
            ]
        }
    }

    private func multiCornerObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        let multiCorner = summary.summary.multiCorner
        return [
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-successful-corner-count",
                status: .derived,
                value: .number(Double(multiCorner.successfulCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-comparison-basis",
                status: .derived,
                value: .string(multiCorner.comparisonBasis.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-failed-corner-count",
                status: .derived,
                value: .number(Double(multiCorner.failedCornerCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-failed-corner-ids",
                status: multiCorner.failedCornerIDs.isEmpty ? .derived : .failed,
                value: .array(multiCorner.failedCornerIDs.map { .string($0) }),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-worst-capacitance-corner-id",
                status: multiCorner.worstCapacitanceCornerID == nil ? .missing : .derived,
                value: optionalStringValue(multiCorner.worstCapacitanceCornerID),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-total-capacitance-spread-f",
                status: .derived,
                value: .number(multiCorner.totalCapacitance.spread),
                unit: "F",
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: spreadMetadata(multiCorner.totalCapacitance)
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-total-capacitance-relative-spread",
                status: multiCorner.totalCapacitance.relativeSpread == nil ? .missing : .derived,
                value: optionalNumberValue(multiCorner.totalCapacitance.relativeSpread),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: spreadMetadata(multiCorner.totalCapacitance)
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-worst-resistance-corner-id",
                status: multiCorner.worstResistanceCornerID == nil ? .missing : .derived,
                value: optionalStringValue(multiCorner.worstResistanceCornerID),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-total-resistance-spread-ohm",
                status: .derived,
                value: .number(multiCorner.totalResistance.spread),
                unit: "ohm",
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: spreadMetadata(multiCorner.totalResistance)
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-total-resistance-relative-spread",
                status: multiCorner.totalResistance.relativeSpread == nil ? .missing : .derived,
                value: optionalNumberValue(multiCorner.totalResistance.relativeSpread),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: spreadMetadata(multiCorner.totalResistance)
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-diagnostic-count",
                status: .derived,
                value: .number(Double(multiCorner.diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "pex-multi-corner-error-diagnostic-count",
                status: .derived,
                value: .number(Double(multiCornerErrorDiagnosticCount(summary))),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func topNetObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        summary.summary.corners.enumerated().flatMap { cornerIndex, corner in
            corner.topNets.enumerated().flatMap { netIndex, net in
                let baseID = topNetChannelBase(cornerIndex: cornerIndex, corner: corner, netIndex: netIndex, net: net)
                let metadata = topNetMetadata(
                    cornerIndex: cornerIndex,
                    corner: corner,
                    netIndex: netIndex,
                    net: net
                )
                return [
                    XcircuiteObservationChannel(
                        channelID: "\(baseID)-total-capacitance-f",
                        label: "PEX top net \(net.name)",
                        status: .observed,
                        value: .number(net.groundCapF + net.couplingCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence,
                        metadata: metadata
                    ),
                    XcircuiteObservationChannel(
                        channelID: "\(baseID)-ground-capacitance-f",
                        status: .observed,
                        value: .number(net.groundCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence,
                        metadata: metadata
                    ),
                    XcircuiteObservationChannel(
                        channelID: "\(baseID)-coupling-capacitance-f",
                        status: .observed,
                        value: .number(net.couplingCapF),
                        unit: "F",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence,
                        metadata: metadata
                    ),
                    XcircuiteObservationChannel(
                        channelID: "\(baseID)-resistance-ohm",
                        status: .observed,
                        value: .number(net.resistanceOhm),
                        unit: "ohm",
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence,
                        metadata: metadata
                    ),
                    XcircuiteObservationChannel(
                        channelID: "\(baseID)-node-count",
                        status: .observed,
                        value: .number(Double(net.nodeCount)),
                        sourceArtifactIDs: [artifactID],
                        confidence: confidence,
                        metadata: metadata
                    ),
                ]
            }
        }
    }

    private func multiCornerTopNetObservationChannels(
        summary: PEXRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        summary.summary.multiCorner.topNetSpreads.enumerated().flatMap { index, spread in
            let baseID = multiCornerNetSpreadChannelBase(index: index, spread: spread)
            let metadata = multiCornerNetSpreadMetadata(index: index, spread: spread)
            return [
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-capacitance-spread-f",
                    label: "PEX multi-corner net \(spread.netName)",
                    status: .derived,
                    value: .number(spread.totalCapacitance.spread),
                    unit: "F",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-total-capacitance-relative-spread",
                    status: spread.totalCapacitance.relativeSpread == nil ? .missing : .derived,
                    value: optionalNumberValue(spread.totalCapacitance.relativeSpread),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-resistance-spread-ohm",
                    status: .derived,
                    value: .number(spread.resistance.spread),
                    unit: "ohm",
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-observed-corner-count",
                    status: .derived,
                    value: .number(Double(spread.observedCornerIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
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
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-gate-status",
                channelID: "pex-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .string(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-summary-artifact",
                channelID: "pex-summary-artifact-present",
                status: .accepted,
                observedValue: .bool(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                metadata: ["artifactID": .string(artifactID)]
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-artifact-completeness-status",
                channelID: "pex-artifact-completeness-status",
                status: completenessStatus(summary.completeness.status),
                observedValue: .string(summary.completeness.status.rawValue),
                residual: summary.completeness.status == .complete ? 0 : Double(summary.completeness.issues.count),
                likelihood: summary.completeness.status == .complete ? 1 : 0,
                confidence: confidence
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-failed-corner-count",
                channelID: "pex-failed-corner-count",
                status: countStatus(aggregate.failedCornerCount),
                observedValue: .number(Double(aggregate.failedCornerCount)),
                residual: Double(aggregate.failedCornerCount),
                likelihood: countLikelihood(aggregate.failedCornerCount),
                confidence: confidence
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-summary-error-diagnostic-count",
                channelID: "pex-summary-error-diagnostic-count",
                status: countStatus(aggregate.summaryErrorDiagnosticCount),
                observedValue: .number(Double(aggregate.summaryErrorDiagnosticCount)),
                residual: Double(aggregate.summaryErrorDiagnosticCount),
                likelihood: countLikelihood(aggregate.summaryErrorDiagnosticCount),
                confidence: confidence
            ),
        ]
    }

    private func multiCornerChannelResults(
        summary: PEXRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        let multiCorner = summary.summary.multiCorner
        let errorDiagnosticCount = multiCornerErrorDiagnosticCount(summary)
        let sharedTechnology = multiCorner.comparisonBasis == .sharedTechnology
        return [
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-multi-corner-shared-technology",
                channelID: "pex-multi-corner-comparison-basis",
                status: sharedTechnology ? .accepted : .rejected,
                observedValue: .string(multiCorner.comparisonBasis.rawValue),
                residual: sharedTechnology ? 0 : 1,
                likelihood: sharedTechnology ? 1 : 0,
                confidence: confidence,
                metadata: [
                    "sharedTechnologyBasis": .bool(sharedTechnology),
                    "requiresFoundryCorrelation": .bool(true),
                ]
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-multi-corner-failed-corner-count",
                channelID: "pex-multi-corner-failed-corner-count",
                status: countStatus(multiCorner.failedCornerCount),
                observedValue: .number(Double(multiCorner.failedCornerCount)),
                residual: Double(multiCorner.failedCornerCount),
                likelihood: countLikelihood(multiCorner.failedCornerCount),
                confidence: confidence,
                metadata: [
                    "failedCornerIDs": .array(multiCorner.failedCornerIDs.map { .string($0) }),
                ]
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "pex-multi-corner-error-diagnostic-count",
                channelID: "pex-multi-corner-error-diagnostic-count",
                status: countStatus(errorDiagnosticCount),
                observedValue: .number(Double(errorDiagnosticCount)),
                residual: Double(errorDiagnosticCount),
                likelihood: countLikelihood(errorDiagnosticCount),
                confidence: confidence,
                diagnostics: multiCorner.diagnostics.map(runActionDiagnostic)
            ),
        ]
    }

    private func cornerChannelResults(
        summary: PEXRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        summary.summary.corners.enumerated().flatMap { index, corner in
            let baseID = cornerChannelBase(index: index, corner: corner)
            let hasIR = corner.parasiticIRArtifactID != nil
            return [
                XcircuiteEvaluationChannelResult(
                    criterionID: "\(baseID)-status",
                    channelID: "\(baseID)-status",
                    status: cornerEvaluationStatus(corner.status),
                    observedValue: .string(corner.status),
                    residual: corner.status == PEXRunStatus.success.rawValue ? 0 : 1,
                    likelihood: corner.status == PEXRunStatus.success.rawValue ? 1 : 0,
                    confidence: confidence,
                    diagnostics: corner.diagnostics.map(runActionDiagnostic),
                    metadata: cornerMetadata(index: index, corner: corner)
                ),
                XcircuiteEvaluationChannelResult(
                    criterionID: "\(baseID)-parasitic-ir-present",
                    channelID: "\(baseID)-parasitic-ir-present",
                    status: hasIR ? .accepted : .rejected,
                    observedValue: .bool(hasIR),
                    residual: hasIR ? 0 : 1,
                    likelihood: hasIR ? 1 : 0,
                    confidence: confidence,
                    metadata: cornerMetadata(index: index, corner: corner)
                ),
            ]
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        var signals: [XcircuiteFeedbackSignal] = []

        if gateStatus == .passed
            && summary.completeness.status == .complete
            && aggregate.failedCornerCount == 0
            && aggregate.summaryErrorDiagnosticCount == 0 {
            signals.append(
                XcircuiteFeedbackSignal(
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
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-artifact-completeness",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-artifact-completeness-status",
                    routingLevel: .structureMapping,
                    severity: summary.completeness.status == .invalid ? .error : .warning,
                    summary: "PEX artifacts are not complete enough for reliable post-layout planning.",
                    residual: Double(summary.completeness.issues.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-manifest", "repair-pex-artifact-production"],
                    confidence: confidence,
                    metadata: completenessMetadata(summary: summary)
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
                XcircuiteFeedbackSignal(
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
                XcircuiteFeedbackSignal(
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
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        switch summary.summary.multiCorner.comparisonBasis {
        case .sharedTechnology:
            return []
        case .perCornerTechnology:
            return [
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-process-specific-comparison",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-comparison-basis",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "PEX corner spread is process-specific; foundry correlation evidence is required before PVT signoff promotion.",
                    residual: 1,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary", "compare-post-layout-metrics"],
                    confidence: confidence,
                    metadata: [
                        "comparisonBasis": .string(PEXExtractorMultiCornerComparisonBasis.perCornerTechnology.rawValue),
                        "requiresCorrelationEvidence": .bool(true),
                    ]
                ),
            ]
        case .unknown:
            return [
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-unknown-comparison-basis",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-comparison-basis",
                    routingLevel: .structureMapping,
                    severity: .warning,
                    summary: "PEX comparison basis is unknown; do not promote the retained spread to a PVT signoff claim.",
                    residual: 1,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-pex-summary"],
                    confidence: confidence,
                    metadata: [
                        "comparisonBasis": .string(PEXExtractorMultiCornerComparisonBasis.unknown.rawValue),
                        "requiresCorrelationEvidence": .bool(true),
                    ]
                ),
            ]
        }
    }

    private func failedCornerSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        summary.summary.corners.enumerated().compactMap { index, corner in
            guard corner.status != PEXRunStatus.success.rawValue || !corner.diagnostics.isEmpty else {
                return nil
            }
            let baseID = cornerChannelBase(index: index, corner: corner)
            return XcircuiteFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-status",
                routingLevel: .structureMapping,
                severity: corner.status == PEXRunStatus.partialSuccess.rawValue ? .warning : .error,
                summary: "PEX corner \(corner.cornerID) ended with status \(corner.status).",
                residual: corner.status == PEXRunStatus.success.rawValue ? 0 : 1,
                affectedArtifactIDs: [artifactID],
                suggestedActions: ["inspect-pex-corner", "repair-pex-extraction-inputs"],
                confidence: confidence,
                metadata: cornerMetadata(index: index, corner: corner)
            )
        }
    }

    private func multiCornerSpreadSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        let multiCorner = summary.summary.multiCorner
        guard multiCorner.successfulCornerCount > 1 else {
            return []
        }

        var signals: [XcircuiteFeedbackSignal] = []
        if multiCorner.totalCapacitance.spread > 0,
           let cornerID = multiCorner.worstCapacitanceCornerID {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-capacitance-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-total-capacitance-spread-f",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX corner \(cornerID) has the highest total capacitance across retained corners.",
                    residual: multiCorner.totalCapacitance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-worst-pex-corner", "compare-post-layout-metrics"],
                    confidence: confidence,
                    metadata: spreadMetadata(multiCorner.totalCapacitance)
                )
            )
        }
        if multiCorner.totalResistance.spread > 0,
           let cornerID = multiCorner.worstResistanceCornerID {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-resistance-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "pex-multi-corner-total-resistance-spread-ohm",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX corner \(cornerID) has the highest total resistance across retained corners.",
                    residual: multiCorner.totalResistance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-worst-pex-corner", "compare-post-layout-metrics"],
                    confidence: confidence,
                    metadata: spreadMetadata(multiCorner.totalResistance)
                )
            )
        }
        if let spread = multiCorner.topNetSpreads.first, spread.totalCapacitance.spread > 0 {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-multi-corner-net-spread",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "\(multiCornerNetSpreadChannelBase(index: 0, spread: spread))-total-capacitance-spread-f",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "PEX net \(spread.netName) has the largest retained corner capacitance spread.",
                    residual: spread.totalCapacitance.spread,
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-parasitic-net-spread", "compare-post-layout-metrics"],
                    confidence: confidence,
                    metadata: multiCornerNetSpreadMetadata(index: 0, spread: spread)
                )
            )
        }

        return signals
    }

    private func dominantNetSignals(
        artifactID: String,
        summary: PEXRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        summary.summary.corners.enumerated().compactMap { cornerIndex, corner in
            guard let net = corner.topNets.first else {
                return nil
            }
            let channelBase = topNetChannelBase(cornerIndex: cornerIndex, corner: corner, netIndex: 0, net: net)
            return XcircuiteFeedbackSignal(
                signalID: "\(channelBase)-post-layout-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(channelBase)-total-capacitance-f",
                routingLevel: .localSurface,
                severity: .info,
                summary: "PEX corner \(corner.cornerID) is dominated by net \(net.name) by capacitance.",
                affectedArtifactIDs: [artifactID],
                suggestedActions: ["inspect-dominant-parasitic-net", "compare-post-layout-metrics"],
                confidence: confidence,
                metadata: topNetMetadata(cornerIndex: cornerIndex, corner: corner, netIndex: 0, net: net)
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

    private func evaluationStatus(
        summary: PEXRunSummaryReport,
        aggregate: AggregateMetrics,
        gateStatus: FlowGateStatus
    ) -> XcircuiteEvaluationStatus {
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

    private func completenessStatus(
        _ status: PEXArtifactCompletenessStatus
    ) -> XcircuiteEvaluationStatus {
        switch status {
        case .complete:
            .accepted
        case .incomplete:
            .inconclusive
        case .invalid:
            .rejected
        }
    }

    private func cornerEvaluationStatus(_ status: String) -> XcircuiteEvaluationStatus {
        switch status {
        case PEXRunStatus.success.rawValue:
            .accepted
        case PEXRunStatus.partialSuccess.rawValue:
            .inconclusive
        default:
            .rejected
        }
    }

    private func countStatus(_ count: Int) -> XcircuiteEvaluationStatus {
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

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> XcircuiteRunActionDiagnostic {
        XcircuiteRunActionDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionDiagnostic(_ diagnostic: PEXRunSummaryDiagnostic) -> XcircuiteRunActionDiagnostic {
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

    private func runActionSeverity(_ severity: String) -> XcircuiteRunActionDiagnosticSeverity {
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

    private func cornerMetadata(
        index: Int,
        corner: PEXCornerParasiticSummary
    ) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "cornerIndex": .number(Double(index)),
            "cornerID": .string(corner.cornerID),
            "status": .string(corner.status),
            "unitSystem": .string(corner.unitSystem),
            "netCount": .number(Double(corner.netCount)),
            "elementCount": .number(Double(corner.elementCount)),
            "topNetCount": .number(Double(corner.topNets.count)),
            "rawOutputArtifactIDs": .array(corner.rawOutputArtifactIDs.map { .string($0) }),
        ]
        if let parasiticIRArtifactID = corner.parasiticIRArtifactID {
            metadata["parasiticIRArtifactID"] = .string(parasiticIRArtifactID)
        }
        if let spefRoundTripArtifactID = corner.spefRoundTripArtifactID {
            metadata["spefRoundTripArtifactID"] = .string(spefRoundTripArtifactID)
        }
        if !corner.diagnostics.isEmpty {
            metadata["diagnostics"] = .array(corner.diagnostics.map { diagnostic in
                .object([
                    "severity": .string(diagnostic.severity),
                    "code": .string(diagnostic.code),
                    "message": .string(diagnostic.message),
                ])
            })
        }
        return metadata
    }

    private func topNetMetadata(
        cornerIndex: Int,
        corner: PEXCornerParasiticSummary,
        netIndex: Int,
        net: PEXNetParasiticSummary
    ) -> [String: XcircuiteJSONValue] {
        [
            "cornerIndex": .number(Double(cornerIndex)),
            "cornerID": .string(corner.cornerID),
            "netIndex": .number(Double(netIndex)),
            "netName": .string(net.name),
            "nodeCount": .number(Double(net.nodeCount)),
            "groundCapacitanceF": .number(net.groundCapF),
            "couplingCapacitanceF": .number(net.couplingCapF),
            "totalCapacitanceF": .number(net.groundCapF + net.couplingCapF),
            "resistanceOhm": .number(net.resistanceOhm),
        ]
    }

    private func multiCornerNetSpreadMetadata(
        index: Int,
        spread: PEXNetCornerSpreadSummary
    ) -> [String: XcircuiteJSONValue] {
        [
            "netIndex": .number(Double(index)),
            "netName": .string(spread.netName),
            "observedCornerIDs": .array(spread.observedCornerIDs.map { .string($0) }),
            "missingCornerIDs": .array(spread.missingCornerIDs.map { .string($0) }),
            "totalCapacitance": .object(spreadMetadata(spread.totalCapacitance)),
            "resistance": .object(spreadMetadata(spread.resistance)),
        ]
    }

    private func spreadMetadata(_ spread: PEXCornerMetricSpreadSummary) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "metric": .string(spread.metric),
            "unit": .string(spread.unit),
            "observedCornerCount": .number(Double(spread.observedCornerCount)),
            "spread": .number(spread.spread),
        ]
        if let minCornerID = spread.minCornerID {
            metadata["minCornerID"] = .string(minCornerID)
        }
        if let minValue = spread.minValue {
            metadata["minValue"] = .number(minValue)
        }
        if let maxCornerID = spread.maxCornerID {
            metadata["maxCornerID"] = .string(maxCornerID)
        }
        if let maxValue = spread.maxValue {
            metadata["maxValue"] = .number(maxValue)
        }
        if let relativeSpread = spread.relativeSpread {
            metadata["relativeSpread"] = .number(relativeSpread)
        }
        return metadata
    }

    private func optionalStringValue(_ value: String?) -> XcircuiteJSONValue {
        value.map { .string($0) } ?? .null
    }

    private func optionalNumberValue(_ value: Double?) -> XcircuiteJSONValue {
        value.map { .number($0) } ?? .null
    }

    private func multiCornerErrorDiagnosticCount(_ summary: PEXRunSummaryReport) -> Int {
        summary.summary.multiCorner.diagnostics.filter { $0.severity == "error" }.count
    }

    private func completenessMetadata(summary: PEXRunSummaryReport) -> [String: XcircuiteJSONValue] {
        [
            "status": .string(summary.completeness.status.rawValue),
            "issues": .array(summary.completeness.issues.map { issue in
                var values: [String: XcircuiteJSONValue] = [
                    "kind": .string(issue.kind.rawValue),
                    "message": .string(issue.message),
                ]
                if let artifactID = issue.artifactID {
                    values["artifactID"] = .string(artifactID)
                }
                if let cornerID = issue.cornerID {
                    values["cornerID"] = .string(cornerID.value)
                }
                if let path = issue.path {
                    values["path"] = .string(path.value)
                }
                return .object(values)
            }),
        ]
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
