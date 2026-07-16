import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LVSEngine

struct LVSSummaryEnvelopeBuilder: Sendable {
    func envelopeReference(
        summary: LVSRunSummaryReport,
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

        let envelope = FlowArtifactEnvelope(
            artifactID: artifactID,
            role: "lvs-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: FlowArtifactProducer(producerID: toolID, toolID: toolID),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: FlowEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate LVS mismatch evidence for stage readiness and repair planning.",
                criteria: criteria,
                requiredArtifactRoles: ["lvs-summary"],
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
                summary: "LVS summary evaluation ended with gate status \(gateStatus.rawValue)."
            )
        )

        return try await context.persistArtifactEnvelope(envelope)
    }

    private func baseCriteria(artifactID: String) -> [FlowEvaluationCriterion] {
        [
            FlowEvaluationCriterion(
                criterionID: "lvs-gate-status",
                channelID: "lvs-gate-status",
                comparator: .equal,
                target: .text(FlowGateStatus.passed.rawValue)
            ),
            FlowEvaluationCriterion(
                criterionID: "lvs-active-mismatch-count",
                channelID: "lvs-active-mismatch-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "lvs-unused-waiver-count",
                channelID: "lvs-unused-waiver-count",
                comparator: .equal,
                target: .scalar(0),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "lvs-tool-evidence",
                channelID: "lvs-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .scalar(1),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "lvs-calibration",
                channelID: "lvs-qualified-calibration",
                comparator: .equal,
                target: .boolean(true),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "lvs-summary-artifact",
                channelID: "lvs-summary-artifact-present",
                comparator: .equal,
                target: .boolean(true),
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
        ]
    }

    private func bucketCriteria(summary: LVSRunSummaryReport) -> [FlowEvaluationCriterion] {
        summary.summary.mismatchBuckets.enumerated().map { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            return FlowEvaluationCriterion(
                criterionID: "\(baseID)-active-count",
                channelID: "\(baseID)-active-count",
                comparator: .equal,
                target: .scalar(0),
                context: bucketContext(index: index, bucket: bucket)
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
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        [
            FlowObservationChannel(
                channelID: "lvs-summary-artifact-present",
                status: .observed,
                value: .boolean(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-gate-status",
                status: .observed,
                value: .text(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                context: FlowEvaluationContext(gateID: "lvs")
            ),
            FlowObservationChannel(
                channelID: "lvs-diagnostic-count",
                status: .observed,
                value: .scalar(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .scalar(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .boolean(hasQualifiedEvidence),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-execution-status",
                status: .observed,
                value: .text(summary.summary.executionStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-verdict",
                status: .observed,
                value: .text(summary.summary.verdict.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-readiness",
                status: .observed,
                value: .text(summary.summary.readiness.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-active-mismatch-count",
                status: .observed,
                value: .scalar(Double(summary.summary.activeMismatchCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-waived-mismatch-count",
                status: .observed,
                value: .scalar(Double(summary.summary.waivedMismatchCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-mismatch-bucket-count",
                status: .observed,
                value: .scalar(Double(summary.summary.mismatchBuckets.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-unused-waiver-count",
                status: .observed,
                value: .scalar(Double(summary.summary.unusedWaiverIDs.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-extracted-layout-netlist-present",
                status: summary.summary.extractedLayoutNetlistURL == nil ? .missing : .observed,
                value: .boolean(summary.summary.extractedLayoutNetlistURL != nil),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-error-diagnostic-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.errorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-waived-error-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.waivedErrorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func policyObservationChannels(
        summary: LVSRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        guard let policy = summary.summary.devicePolicySummary else {
            return [
                FlowObservationChannel(
                    channelID: "lvs-device-policy-present",
                    status: .missing,
                    value: .boolean(false),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence
                ),
            ]
        }
        return [
            FlowObservationChannel(
                channelID: "lvs-device-policy-present",
                status: .observed,
                value: .boolean(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-device-policy-status",
                status: .observed,
                value: .text(policy.status.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-device-policy-applied-rule-count",
                status: .observed,
                value: .scalar(Double(policy.appliedRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-device-policy-ignored-rule-count",
                status: .observed,
                value: .scalar(Double(policy.ignoredRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "lvs-device-policy-unobserved-rule-count",
                status: .observed,
                value: .scalar(Double(policy.unobservedRuleCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func bucketObservationChannels(
        summary: LVSRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        summary.summary.mismatchBuckets.enumerated().flatMap { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            let context = bucketContext(index: index, bucket: bucket)
            return [
                FlowObservationChannel(
                    channelID: "\(baseID)-active-count",
                    label: bucketLabel(bucket),
                    status: .observed,
                    value: .scalar(Double(bucket.activeCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-waived-count",
                    status: .observed,
                    value: .scalar(Double(bucket.waivedCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-layout-count",
                    status: bucket.layoutCount == nil ? .missing : .observed,
                    value: bucket.layoutCount.map { .scalar(Double($0)) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-schematic-count",
                    status: bucket.schematicCount == nil ? .missing : .observed,
                    value: bucket.schematicCount.map { .scalar(Double($0)) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-layout-port-count",
                    status: .observed,
                    value: .scalar(Double(bucket.layoutPorts.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-schematic-port-count",
                    status: .observed,
                    value: .scalar(Double(bucket.schematicPorts.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
            ]
        }
    }

    private func baseChannelResults(
        summary: LVSRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                criterionID: "lvs-gate-status",
                channelID: "lvs-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .text(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            FlowEvaluationChannelResult(
                criterionID: "lvs-summary-artifact",
                channelID: "lvs-summary-artifact-present",
                status: .accepted,
                observedValue: .boolean(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
            FlowEvaluationChannelResult(
                criterionID: "lvs-active-mismatch-count",
                channelID: "lvs-active-mismatch-count",
                status: countStatus(summary.summary.activeMismatchCount),
                observedValue: .scalar(Double(summary.summary.activeMismatchCount)),
                residual: Double(summary.summary.activeMismatchCount),
                likelihood: countLikelihood(summary.summary.activeMismatchCount),
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "lvs-unused-waiver-count",
                channelID: "lvs-unused-waiver-count",
                status: summary.summary.unusedWaiverIDs.isEmpty ? .accepted : .needsHumanReview,
                observedValue: .scalar(Double(summary.summary.unusedWaiverIDs.count)),
                residual: Double(summary.summary.unusedWaiverIDs.count),
                likelihood: countLikelihood(summary.summary.unusedWaiverIDs.count),
                confidence: confidence
            ),
        ]
    }

    private func bucketChannelResults(
        summary: LVSRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        summary.summary.mismatchBuckets.enumerated().map { index, bucket in
            let baseID = bucketChannelBase(index: index, bucket: bucket)
            return FlowEvaluationChannelResult(
                criterionID: "\(baseID)-active-count",
                channelID: "\(baseID)-active-count",
                status: countStatus(bucket.activeCount),
                observedValue: .scalar(Double(bucket.activeCount)),
                residual: Double(bucket.activeCount),
                likelihood: countLikelihood(bucket.activeCount),
                confidence: confidence,
                context: bucketContext(index: index, bucket: bucket)
            )
        }
    }

    private func feedbackSignals(
        artifactID: String,
        summary: LVSRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        var signals: [FlowFeedbackSignal] = []
        let activeBuckets = summary.summary.mismatchBuckets.enumerated()
            .filter { $0.element.activeCount > 0 }

        if gateStatus == .passed && activeBuckets.isEmpty {
            signals.append(
                FlowFeedbackSignal(
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
            return FlowFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-active-count",
                routingLevel: routingLevel(for: bucket),
                severity: .error,
                summary: "LVS mismatch \(bucketLabel(bucket)) has \(bucket.activeCount) active mismatch(es).",
                residual: Double(bucket.activeCount),
                affectedArtifactIDs: [artifactID],
                suggestedActions: suggestedActions(for: bucket),
                confidence: confidence
            )
        })

        if !summary.summary.unusedWaiverIDs.isEmpty {
            signals.append(
                FlowFeedbackSignal(
                    signalID: "\(artifactID)-unused-waivers",
                    sourceEvaluationID: "\(artifactID)-evaluation",
                    channelID: "lvs-unused-waiver-count",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "LVS summary contains unused waiver IDs.",
                    residual: Double(summary.summary.unusedWaiverIDs.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-lvs-waivers", "remove-stale-waivers"],
                    confidence: confidence
                )
            )
        }

        if gateStatus != .passed && activeBuckets.isEmpty {
            signals.append(
                FlowFeedbackSignal(
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
                FlowFeedbackSignal(
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
        summary: LVSRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> FlowEvaluationStatus {
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

    private func countStatus(_ count: Int) -> FlowEvaluationStatus {
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

    private func routingLevel(for bucket: LVSMismatchBucketSummary) -> FlowFeedbackRoutingLevel {
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

    private func bucketContext(index: Int, bucket: LVSMismatchBucketSummary) -> FlowEvaluationContext {
        FlowEvaluationContext(
            category: bucket.category,
            ruleID: bucket.ruleID,
            parameterName: bucket.parameterName,
            componentSignature: bucket.componentSignature,
            layoutModel: bucket.layoutModel,
            schematicModel: bucket.schematicModel,
            layoutCount: bucket.layoutCount,
            schematicCount: bucket.schematicCount,
            bucketIndex: index,
            activeCount: bucket.activeCount,
            waivedCount: bucket.waivedCount,
            layoutPorts: bucket.layoutPorts,
            schematicPorts: bucket.schematicPorts,
            suggestedActions: bucket.suggestedFixes
        )
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
