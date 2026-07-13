import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation

struct DRCSummaryEnvelopeBuilder: Sendable {
    /// Projects the canonical stage artifacts through the legacy envelope
    /// record until DesignFlowKernel adopts Foundation references natively.
    func envelopeReference(
        summary: DRCRunSummaryReport,
        summaryArtifactID: String,
        stageArtifacts: [ArtifactReference],
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let legacyArtifacts = FoundationFlowProjection.legacyReferences(from: stageArtifacts)
        let legacyEnvelope = try envelopeReference(
            summary: summary,
            summaryArtifactID: summaryArtifactID,
            stageArtifacts: legacyArtifacts,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            stageID: stageID,
            toolID: toolID,
            context: context
        )
        return try FoundationFlowProjection.artifactReference(from: legacyEnvelope, role: .output)
    }

    func envelopeReference(
        summary: DRCRunSummaryReport,
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
                "DRC summary artifact must have an artifact ID before envelope creation."
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
        ) + bucketObservationChannels(
            summary: summary,
            artifactID: artifactID,
            confidence: confidence
        )
        let channelResults = baseChannelResults(
            summary: summary,
            artifactID: artifactID,
            gateStatus: gateStatus,
            diagnostics: diagnostics,
            confidence: confidence
        ) + bucketChannelResults(summary: summary, confidence: confidence)

        let envelope = XcircuiteArtifactEnvelope(
            artifactID: artifactID,
            role: "drc-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: XcircuiteArtifactProducer(
                producerID: toolID,
                toolID: toolID
            ),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: XcircuiteEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate DRC violation evidence for stage readiness and repair planning.",
                criteria: criteria,
                requiredArtifactRoles: ["drc-summary"],
                confidence: XcircuiteEvidenceConfidence(value: 0.5, posteriorVariance: 0.5, calibrated: false),
                metadata: [
                    "backendID": .string(summary.summary.backendID),
                    "topCell": .string(summary.summary.topCell),
                    "activeViolationCount": .number(Double(summary.summary.activeViolationCount)),
                    "violationBucketCount": .number(Double(summary.summary.violationBuckets.count)),
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
                summary: "DRC summary evaluation ended with gate status \(gateStatus.rawValue).",
                metadata: [
                    "activeViolationCount": .number(Double(summary.summary.activeViolationCount)),
                    "waivedViolationCount": .number(Double(summary.summary.waivedViolationCount)),
                    "unusedWaiverCount": .number(Double(summary.summary.unusedWaiverIDs.count)),
                ]
            ),
            metadata: [
                "gateID": .string("drc"),
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
                criterionID: "drc-gate-status",
                channelID: "drc-gate-status",
                comparator: .equal,
                target: .string(FlowGateStatus.passed.rawValue)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "drc-active-violation-count",
                channelID: "drc-active-violation-count",
                comparator: .equal,
                target: .number(0)
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "drc-unused-waiver-count",
                channelID: "drc-unused-waiver-count",
                comparator: .equal,
                target: .number(0),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "drc-tool-evidence",
                channelID: "drc-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .number(1),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "drc-calibration",
                channelID: "drc-qualified-calibration",
                comparator: .equal,
                target: .bool(true),
                required: false
            ),
            XcircuiteEvaluationCriterion(
                criterionID: "drc-summary-artifact",
                channelID: "drc-summary-artifact-present",
                comparator: .equal,
                target: .bool(true),
                metadata: ["artifactID": .string(artifactID)]
            ),
        ]
    }

    private func bucketCriteria(summary: DRCRunSummaryReport) -> [XcircuiteEvaluationCriterion] {
        summary.summary.violationBuckets.enumerated().map { index, bucket in
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
        summary: DRCRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        [
            XcircuiteObservationChannel(
                channelID: "drc-summary-artifact-present",
                status: .observed,
                value: .bool(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-gate-status",
                status: .observed,
                value: .string(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                metadata: ["gateID": .string("drc")]
            ),
            XcircuiteObservationChannel(
                channelID: "drc-diagnostic-count",
                status: .observed,
                value: .number(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .number(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .bool(hasQualifiedEvidence),
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-completed",
                status: .observed,
                value: .bool(summary.summary.completed),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-passed",
                status: .observed,
                value: .bool(summary.summary.passed),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-active-violation-count",
                status: .observed,
                value: .number(Double(summary.summary.activeViolationCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-waived-violation-count",
                status: .observed,
                value: .number(Double(summary.summary.waivedViolationCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-violation-bucket-count",
                status: .observed,
                value: .number(Double(summary.summary.violationBuckets.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-unused-waiver-count",
                status: .observed,
                value: .number(Double(summary.summary.unusedWaiverIDs.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-info-diagnostic-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.infoCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-warning-diagnostic-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.warningCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-error-diagnostic-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.errorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            XcircuiteObservationChannel(
                channelID: "drc-waived-error-count",
                status: .observed,
                value: .number(Double(summary.summary.diagnosticSummary.waivedErrorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func bucketObservationChannels(
        summary: DRCRunSummaryReport,
        artifactID: String,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteObservationChannel] {
        summary.summary.violationBuckets.enumerated().flatMap { index, bucket in
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
                    label: "\(bucketLabel(bucket)) waived",
                    status: .observed,
                    value: .number(Double(bucket.waivedCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-max-measured",
                    label: "\(bucketLabel(bucket)) max measured",
                    status: bucket.maxMeasured == nil ? .missing : .observed,
                    value: bucket.maxMeasured.map { .number($0) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-required",
                    label: "\(bucketLabel(bucket)) required",
                    status: bucket.required == nil ? .missing : .observed,
                    value: bucket.required.map { .number($0) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-related-shape-count",
                    status: .observed,
                    value: .number(Double(bucket.relatedShapeIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-related-net-count",
                    status: .observed,
                    value: .number(Double(bucket.relatedNetIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    metadata: metadata
                ),
                XcircuiteObservationChannel(
                    channelID: "\(baseID)-suggested-fix-count",
                    status: .observed,
                    value: .number(Double(bucket.suggestedFixes.count)),
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
        summary: DRCRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                criterionID: "drc-gate-status",
                channelID: "drc-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .string(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "drc-summary-artifact",
                channelID: "drc-summary-artifact-present",
                status: .accepted,
                observedValue: .bool(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                metadata: ["artifactID": .string(artifactID)]
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "drc-active-violation-count",
                channelID: "drc-active-violation-count",
                status: countStatus(summary.summary.activeViolationCount),
                observedValue: .number(Double(summary.summary.activeViolationCount)),
                residual: Double(summary.summary.activeViolationCount),
                likelihood: countLikelihood(summary.summary.activeViolationCount),
                confidence: confidence
            ),
            XcircuiteEvaluationChannelResult(
                criterionID: "drc-unused-waiver-count",
                channelID: "drc-unused-waiver-count",
                status: summary.summary.unusedWaiverIDs.isEmpty ? .accepted : .needsHumanReview,
                observedValue: .number(Double(summary.summary.unusedWaiverIDs.count)),
                residual: Double(summary.summary.unusedWaiverIDs.count),
                likelihood: countLikelihood(summary.summary.unusedWaiverIDs.count),
                confidence: confidence
            ),
        ]
    }

    private func bucketChannelResults(
        summary: DRCRunSummaryReport,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteEvaluationChannelResult] {
        summary.summary.violationBuckets.enumerated().map { index, bucket in
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: XcircuiteEvidenceConfidence
    ) -> [XcircuiteFeedbackSignal] {
        var signals: [XcircuiteFeedbackSignal] = []
        let activeBuckets = summary.summary.violationBuckets.filter { $0.activeCount > 0 }

        if gateStatus == .passed && activeBuckets.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-continue",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "drc-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "DRC summary is usable as downstream evidence.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["continue-flow"],
                    confidence: confidence
                )
            )
        }

        signals.append(contentsOf: activeBuckets.enumerated().map { activeIndex, bucket in
            let originalIndex = summary.summary.violationBuckets.firstIndex(of: bucket) ?? activeIndex
            let baseID = bucketChannelBase(index: originalIndex, bucket: bucket)
            return XcircuiteFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-active-count",
                routingLevel: .localSurface,
                severity: .error,
                summary: "DRC rule \(bucketLabel(bucket)) has \(bucket.activeCount) active violation(s).",
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
                    channelID: "drc-unused-waiver-count",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "DRC summary contains unused waiver IDs.",
                    residual: Double(summary.summary.unusedWaiverIDs.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-drc-waivers", "remove-stale-waivers"],
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
                    channelID: "drc-gate-status",
                    routingLevel: .structureMapping,
                    severity: gateStatus == .failed ? .error : .warning,
                    summary: "DRC result did not provide active violation buckets for repair planning.",
                    residual: residual(summary: summary, gateStatus: gateStatus),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-drc-summary", "inspect-drc-run-log"],
                    confidence: confidence
                )
            )
        }

        if signals.isEmpty {
            signals.append(
                XcircuiteFeedbackSignal(
                    signalID: "\(artifactID)-review-routing",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "drc-gate-status",
                    routingLevel: .localSurface,
                    severity: .info,
                    summary: "DRC summary has no active repair feedback.",
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-drc-summary"],
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> XcircuiteEvaluationStatus {
        if gateStatus == .blocked {
            return .blocked
        }
        if !summary.summary.completed || gateStatus == .incomplete {
            return .inconclusive
        }
        if summary.summary.activeViolationCount > 0 || gateStatus == .failed {
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> Double {
        if summary.summary.activeViolationCount > 0 {
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> Double {
        if summary.summary.activeViolationCount > 0 {
            return Double(summary.summary.activeViolationCount)
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

    private func suggestedActions(for bucket: DRCViolationBucketSummary) -> [String] {
        var actions = bucket.suggestedFixes
        actions.append("inspect-drc-violation")
        actions.append("generate-planning-problem")
        actions.append("apply-drc-repair-hint")
        return Array(Set(actions)).sorted()
    }

    private func bucketChannelBase(index: Int, bucket: DRCViolationBucketSummary) -> String {
        "drc-rule-\(index)-\(slug(bucketLabel(bucket)))"
    }

    private func bucketLabel(_ bucket: DRCViolationBucketSummary) -> String {
        if let ruleID = bucket.ruleID, !ruleID.isEmpty {
            return ruleID
        }
        if let kind = bucket.kind, !kind.isEmpty {
            return kind
        }
        if let layer = bucket.layer, !layer.isEmpty {
            return layer
        }
        return "bucket"
    }

    private func bucketMetadata(
        index: Int,
        bucket: DRCViolationBucketSummary
    ) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "bucketIndex": .number(Double(index)),
            "activeCount": .number(Double(bucket.activeCount)),
            "waivedCount": .number(Double(bucket.waivedCount)),
            "relatedShapeIDs": .array(bucket.relatedShapeIDs.map { .string($0) }),
            "relatedNetIDs": .array(bucket.relatedNetIDs.map { .string($0) }),
            "suggestedFixes": .array(bucket.suggestedFixes.map { .string($0) }),
        ]
        if let ruleID = bucket.ruleID {
            metadata["ruleID"] = .string(ruleID)
        }
        if let kind = bucket.kind {
            metadata["kind"] = .string(kind)
        }
        if let layer = bucket.layer {
            metadata["layer"] = .string(layer)
        }
        if let maxMeasured = bucket.maxMeasured {
            metadata["maxMeasured"] = .number(maxMeasured)
        }
        if let required = bucket.required {
            metadata["required"] = .number(required)
        }
        if let region = bucket.representativeRegion {
            metadata["representativeRegion"] = .object([
                "x": .number(region.x),
                "y": .number(region.y),
                "width": .number(region.width),
                "height": .number(region.height),
            ])
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
