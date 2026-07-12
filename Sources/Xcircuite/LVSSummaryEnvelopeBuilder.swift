import DesignFlowKernel
import Foundation
import LVSEngine
import XcircuitePackage

struct LVSSummaryEnvelopeBuilder: Sendable {
    func envelopeReference(
        summary: LVSRunSummaryReport,
        summaryArtifactID: String,
        stageArtifacts: [XcircuiteFileReference],
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        guard let summaryArtifact = stageArtifacts.first(where: { $0.artifactID == summaryArtifactID }) else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: stageID)
        }
        guard let artifactID = summaryArtifact.artifactID else {
            throw XcircuiteRuntimeError.invalidInputReference(
                "LVS summary artifact must have an artifact ID before envelope creation."
            )
        }

        let hasQualifiedEvidence = hasQualifiedEvidence(context: context, toolID: toolID)
        let toolEvidenceCount = context.healthResults[toolID]?.evidence.count ?? 0
        let confidence = confidence(hasQualifiedEvidence: hasQualifiedEvidence)
        let criteria = baseCriteria(artifactID: artifactID) + bucketCriteria(summary: summary)
        let channels = baseObservationChannels(
            summary: summary,
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            toolEvidenceCount: toolEvidenceCount,
            hasQualifiedEvidence: hasQualifiedEvidence,
            confidence: confidence
        ) + policyObservationChannels(summary: summary, artifactID: artifactID, confidence: confidence)
            + bucketObservationChannels(summary: summary, artifactID: artifactID, confidence: confidence)
        let channelResults = baseChannelResults(
            summary: summary,
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            confidence: confidence
        ) + bucketChannelResults(summary: summary, confidence: confidence)

        let envelope = XcircuiteArtifactEnvelope(
            artifactID: artifactID,
            role: "lvs-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: XcircuiteArtifactProducer(producerID: toolID, toolID: toolID),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: XcircuiteEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate LVS mismatch evidence for stage readiness and repair planning.",
                criteria: criteria,
                requiredArtifactRoles: ["lvs-summary"],
                confidence: XcircuiteEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false),
                metadata: [
                    "backendID": .string(summary.summary.backendID),
                    "topCell": .string(summary.summary.topCell),
                    "layoutInputKind": .string(summary.summary.layoutInputKind),
                    "executionStatus": .string(summary.summary.executionStatus.rawValue),
                    "verdict": .string(summary.summary.verdict.rawValue),
                    "readiness": .string(summary.summary.readiness.rawValue),
                    "activeMismatchCount": .number(Double(summary.summary.activeMismatchCount)),
                    "mismatchBucketCount": .number(Double(summary.summary.mismatchBuckets.count)),
                ]
            ),
            observationSet: XcircuiteObservationSet(
                observationSetID: "\(artifactID)-observations",
                specID: "\(artifactID)-evaluation-spec",
                channels: channels,
                confidence: confidence,
                metadata: [
                    "backendID": .string(summary.summary.backendID),
                    "toolName": .string(summary.summary.toolName),
                    "topCell": .string(summary.summary.topCell),
                    "layoutInputKind": .string(summary.summary.layoutInputKind),
                    "executionStatus": .string(summary.summary.executionStatus.rawValue),
                    "verdict": .string(summary.summary.verdict.rawValue),
                    "readiness": .string(summary.summary.readiness.rawValue),
                ]
            ),
            evaluationResult: XcircuiteEvaluationResult(
                evaluationID: "\(artifactID)-evaluation",
                specID: "\(artifactID)-evaluation-spec",
                status: evaluationStatus(summary: summary, gateStatus: gateStatus),
                likelihood: likelihood(summary: summary, gateStatus: gateStatus),
                residual: residual(summary: summary, gateStatus: gateStatus),
                confidence: confidence,
                channelResults: channelResults,
                feedbackSignals: feedbackSignals(
                    artifactID: artifactID,
                    summary: summary,
                    gateStatus: gateStatus,
                    confidence: confidence
                ),
                summary: "LVS summary evaluation ended with gate status \(gateStatus.rawValue).",
                metadata: [
                    "activeMismatchCount": .number(Double(summary.summary.activeMismatchCount)),
                    "waivedMismatchCount": .number(Double(summary.summary.waivedMismatchCount)),
                    "unusedWaiverCount": .number(Double(summary.summary.unusedWaiverIDs.count)),
                    "blockingReasonCount": .number(Double(summary.summary.blockingReasons.count)),
                ]
            ),
            metadata: [
                "gateID": .string("lvs"),
                "gateStatus": .string(gateStatus.rawValue),
                "stageID": .string(stageID),
                "toolID": .string(toolID),
            ]
        )

        return try context.packageStore.writeArtifactEnvelope(
            envelope,
            runID: context.runID,
            inProjectAt: context.projectRoot
        )
    }

    private func baseCriteria(artifactID: String) -> [XcircuiteEvaluationCriterion] {
        [
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-gate-status",
                channelID: "lvs-gate-status",
                comparator: .equal,
                target: .string(FlowGateStatus.passed.rawValue)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-active-mismatch-count",
                channelID: "lvs-active-mismatch-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-unused-waiver-count",
                channelID: "lvs-unused-waiver-count",
                comparator: .equal,
                target: .number(0),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-tool-evidence",
                channelID: "lvs-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .number(1),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-calibration",
                channelID: "lvs-qualified-calibration",
                comparator: .equal,
                target: .bool(true),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "lvs-summary-artifact",
                channelID: "lvs-summary-artifact-present",
                comparator: .equal,
                target: .bool(true),
                metadata: ["artifactID": .string(artifactID)]
            ),
        ]
    }

    private func bucketCriteria(summary: LVSRunSummaryReport) -> [XcircuiteEvaluationCriterion] {
        summary.summary.mismatchBuckets.enumerated().map { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            return XcircuiteEvaluationCriterion(
                criterionID: "\(baseID)-active-count",
                channelID: "\(baseID)-active-count",
                comparator: .equal,
                target: .number(0),
                metadata: bucketMetadata(index: index, bucket: bucket)
            )
        }
    }

    private func baseObservationChannels(
        summary: LVSRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        [
            XcircuiteObservationChannel(
                channelID: "lvs-summary-artifact-present",
                status: .observed,
                value: .bool(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-gate-status",
                status: .observed,
                value: .string(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: ["gateID": .string("lvs")]
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-diagnostic-count",
                status: .observed,
                value: .number(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .number(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .bool(hasQualifiedEvidence),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-execution-status",
                status: .observed,
                value: .string(summary.summary.executionStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-verdict",
                status: .observed,
                value: .string(summary.summary.verdict.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-readiness",
                status: .observed,
                value: .string(summary.summary.readiness.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-active-mismatch-count",
                status: .observed,
                value: .number(Double(summary.summary.activeMismatchCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-waived-mismatch-count",
                status: .observed,
                value: .number(Double(summary.summary.waivedMismatchCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-mismatch-bucket-count",
                status: .observed,
                value: .number(Double(summary.summary.mismatchBuckets.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-unused-waiver-count",
                status: .observed,
                value: .number(Double(summary.summary.unusedWaiverIDs.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-extracted-layout-netlist-present",
                status: summary.summary.extractedLayoutNetlistURL == nil ? .missing : .observed,
                value: .bool(summary.summary.extractedLayoutNetlistURL != nil),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-error-diagnostic-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.errorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-waived-error-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.waivedErrorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func policyObservationChannels(
        summary: LVSRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        guard let policy = summary.summary.devicePolicySummary else {
            return [
                XcircuiteObservationChannel(
                    channelID: "lvs-device-policy-present",
                    status: .missing,
                    value: .bool(false),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
            ]
        }
        return [
            XcircuiteObservationChannel(
                channelID: "lvs-device-policy-present",
                status: .observed,
                value: .bool(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-device-policy-status",
                status: .observed,
                value: .string(policy.status.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-device-policy-applied-rule-count",
                status: .observed,
                value: .number(Double(policy.appliedRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-device-policy-ignored-rule-count",
                status: .observed,
                value: .number(Double(policy.ignoredRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "lvs-device-policy-unobserved-rule-count",
                status: .observed,
                value: .number(Double(policy.unobservedRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func bucketObservationChannels(
        summary: LVSRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        summary.summary.mismatchBuckets.enumerated().flatMap { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            let metadata = bucketMetadata(index: index, bucket: bucket)
            return [
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-active-count",
                    label: bucketLabel(bucket),
                    status: .observed,
                    value: .number(Double(bucket.activeCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-waived-count",
                    status: .observed,
                    value: .number(Double(bucket.waivedCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-layout-count",
                    status: bucket.layoutCount == nil ? .missing : .observed,
                    value: bucket.layoutCount.map { .number(Double($0)) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-schematic-count",
                    status: bucket.schematicCount == nil ? .missing : .observed,
                    value: bucket.schematicCount.map { .number(Double($0)) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-layout-port-count",
                    status: .observed,
                    value: .number(Double(bucket.layoutPorts.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-schematic-port-count",
                    status: .observed,
                    value: .number(Double(bucket.schematicPorts.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-suggested-fixes",
                    status: bucket.suggestedFixes.isEmpty ? .missing : .observed,
                    value: .array(bucket.suggestedFixes.map { .string($0) }),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
            ]
        }
    }

    private func baseChannelResults(
        summary: LVSRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                criterionID: "lvs-gate-status",
                channelID: "lvs-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .string(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "lvs-summary-artifact",
                channelID: "lvs-summary-artifact-present",
                status: .accepted,
                observedValue: .bool(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                metadata: ["artifactID": .string(artifactID)]
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "lvs-active-mismatch-count",
                channelID: "lvs-active-mismatch-count",
                status: countStatus(summary.summary.activeMismatchCount),
                observedValue: .number(Double(summary.summary.activeMismatchCount)),
                residual: Double(summary.summary.activeMismatchCount),
                likelihood: countLikelihood(summary.summary.activeMismatchCount),
                confidence: confidence
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "lvs-unused-waiver-count",
                channelID: "lvs-unused-waiver-count",
                status: summary.summary.unusedWaiverIDs.isEmpty ? .accepted : .needsHumanReview,
                observedValue: .number(Double(summary.summary.unusedWaiverIDs.count)),
                residual: Double(summary.summary.unusedWaiverIDs.count),
                likelihood: countLikelihood(summary.summary.unusedWaiverIDs.count),
                confidence: confidence
            ),
        ]
    }

    private func bucketChannelResults(
        summary: LVSRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        summary.summary.mismatchBuckets.enumerated().map { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            return XcircuiteEvaluationChannelResult(
                criterionID: "\(baseID)-active-count",
                channelID: "\(baseID)-active-count",
                status: countStatus(bucket.activeCount),
                observedValue: .number(Double(bucket.activeCount)),
                residual: Double(bucket.activeCount),
                likelihood: countLikelihood(bucket.activeCount),
                confidence: confidence,
                metadata: bucketMetadata(index: index, bucket: bucket)
            )
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: LVSRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        var signals: [XcircuiteFeedbackSignal] = []
        let activeBuckets = summary.summary.mismatchBuckets.enumerated()
            .filter { $0.element.activeCount > 0 }

        if gateStatus == .passed && activeBuckets.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-continue",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "lvs-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "LVS summary is usable as downstream evidence.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["continue-flow"],
                    confidence: confidence
                )
            )
        }

        signals.append(contentsOf: activeBuckets.map { indexedBucket in
            let originalIndex = indexedBucket.offset
            let bucket = indexedBucket.element
            let baseID = bucketChannelBase(index: originalIndex, bucket: bucket)
            return XcircuiteFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-active-count",
                routingLevel: routingLevel(for: bucket),
                severity: .error,
                summary: "LVS mismatch \(bucketLabel(bucket)) has \(bucket.activeCount) active mismatch(es).",
                residual: Double(bucket.activeCount),
                affectedArtifactIDs: [artifactID],
                suggestedActions: suggestedActions(for: bucket),
                confidence: confidence,
                metadata: bucketMetadata(index: originalIndex, bucket: bucket)
            )
        })

        if !summary.summary.unusedWaiverIDs.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-unused-waivers",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "lvs-unused-waiver-count",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "LVS summary contains unused waiver IDs.",
                    residual: Double(summary.summary.unusedWaiverIDs.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-lvs-waivers", "remove-stale-waivers"],
                    confidence: confidence,
                    metadata: [
                        "unusedWaiverIDs": .array(summary.summary.unusedWaiverIDs.map { .string($0) }),
                    ]
                )
            )
        }

        if gateStatus != .passed && activeBuckets.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-incomplete-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "lvs-gate-status",
                    routingLevel: .structureMapping,
                    severity: gateStatus == .failed ? .error : .warning,
                    summary: "LVS result did not provide active mismatch buckets for repair planning.",
                    residual: residual(summary: summary, gateStatus: gateStatus),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-lvs-summary", "inspect-lvs-run-log"],
                    confidence: confidence
                )
            )
        }

        if signals.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-review-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "lvs-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "LVS summary has no active repair feedback.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-lvs-summary"],
                    confidence: confidence
                )
            )
        }

        return signals
    }

    private func dependencies(
        from artifacts: [XcircuiteFileReference],
        excluding summaryArtifact: XcircuiteFileReference
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
        summary: LVSRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> XcircuiteEvaluationStatus {
        if gateStatus == .blocked || summary.summary.readiness == .blocked {
            return .blocked
        }
        if summary.summary.executionStatus != .completed || gateStatus == .incomplete {
            return .inconclusive
        }
        if summary.summary.activeMismatchCount > 0 || gateStatus == .failed {
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

    private func countStatus(_ count: Int) -> XcircuiteEvaluationStatus {
        count == 0 ? .accepted : .rejected
    }

    private func likelihood(
        summary: LVSRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> Double {
        if summary.summary.activeMismatchCount > 0 {
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

    private func residual(summary: LVSRunSummaryReport, gateStatus: FlowGateStatus) -> Double {
        if summary.summary.activeMismatchCount > 0 {
            return Double(summary.summary.activeMismatchCount)
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

    private func routingLevel(for bucket: LVSMismatchBucketSummary) -> XcircuiteFeedbackRoutingLevel {
        if requiresPolicyRepair(bucket) {
            return .structureMapping
        }
        return .localSurface
    }

    private func suggestedActions(for bucket: LVSMismatchBucketSummary) -> [String] {
        var actions = bucket.suggestedFixes
        actions.append("inspect-lvs-mismatch")
        actions.append("generate-planning-problem")
        if requiresPolicyRepair(bucket) {
            actions.append("formulate-lvs-policy-repair")
        } else if bucket.parameterName != nil {
            actions.append("edit-netlist-parameter")
        } else {
            actions.append("repair-layout-or-schematic-mapping")
        }
        return Array(Set(actions)).sorted()
    }

    private func requiresPolicyRepair(_ bucket: LVSMismatchBucketSummary) -> Bool {
        let rule = bucket.ruleID?.lowercased() ?? ""
        let category = bucket.category?.lowercased() ?? ""
        return rule.contains("equivalence")
            || rule.contains("policy")
            || rule.contains("blackbox")
            || category.contains("equivalence")
            || category.contains("policy")
    }

    private func bucketChannelBase(index: Int, bucket: LVSMismatchBucketSummary) -> String {
        "lvs-mismatch-\(index)-\(slug(bucketLabel(bucket)))"
    }

    private func bucketLabel(_ bucket: LVSMismatchBucketSummary) -> String {
        if let ruleID = bucket.ruleID, !ruleID.isEmpty {
            return ruleID
        }
        if let category = bucket.category, !category.isEmpty {
            return category
        }
        if let parameterName = bucket.parameterName, !parameterName.isEmpty {
            return parameterName
        }
        if let componentSignature = bucket.componentSignature, !componentSignature.isEmpty {
            return componentSignature
        }
        return "bucket"
    }

    private func bucketMetadata(index: Int, bucket: LVSMismatchBucketSummary) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "bucketIndex": .number(Double(index)),
            "activeCount": .number(Double(bucket.activeCount)),
            "waivedCount": .number(Double(bucket.waivedCount)),
            "layoutPorts": .array(bucket.layoutPorts.map { .string($0) }),
            "schematicPorts": .array(bucket.schematicPorts.map { .string($0) }),
            "suggestedFixes": .array(bucket.suggestedFixes.map { .string($0) }),
        ]
        if let ruleID = bucket.ruleID {
            metadata["ruleID"] = .string(ruleID)
        }
        if let category = bucket.category {
            metadata["category"] = .string(category)
        }
        if let componentSignature = bucket.componentSignature {
            metadata["componentSignature"] = .string(componentSignature)
        }
        if let parameterName = bucket.parameterName {
            metadata["parameterName"] = .string(parameterName)
        }
        if let layoutModel = bucket.layoutModel {
            metadata["layoutModel"] = .string(layoutModel)
        }
        if let schematicModel = bucket.schematicModel {
            metadata["schematicModel"] = .string(schematicModel)
        }
        if let layoutCount = bucket.layoutCount {
            metadata["layoutCount"] = .number(Double(layoutCount))
        }
        if let schematicCount = bucket.schematicCount {
            metadata["schematicCount"] = .number(Double(schematicCount))
        }
        return metadata
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
        return compact.isEmpty ? "bucket" : compact
    }
}
