import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation

struct DRCSummaryEnvelopeBuilder: Sendable {
    func envelopeReference(
        summary: DRCRunSummaryReport,
        summaryArtifactID: String,
        stageArtifacts: [ArtifactReference],
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        stageID: String,
        toolID: String,
        producer: ProducerIdentity,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        guard let summaryArtifact = stageArtifacts.first(where: { $0.artifactID == summaryArtifactID }) else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: stageID)
        }
        let artifactID = summaryArtifact.artifactID

        let hasQualifiedEvidence = hasQualifiedEvidence(
            context: context,
            toolID: toolID,
            producer: producer
        )
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

        let envelope = FlowArtifactEnvelope(
            artifactID: artifactID,
            role: "drc-summary",
            stageID: stageID,
            reference: summaryArtifact,
            producer: FlowArtifactProducer(identity: producer),
            dependencies: dependencies(from: stageArtifacts, excluding: summaryArtifact),
            evaluationSpec: FlowEvaluationSpec(
                specID: "\(artifactID)-evaluation-spec",
                objective: "Evaluate DRC violation evidence for stage readiness and repair planning.",
                criteria: criteria,
                requiredArtifactRoles: ["drc-summary"],
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
                summary: "DRC summary evaluation ended with gate status \(gateStatus.rawValue)."
            )
        )

        return try await context.persistArtifactEnvelope(envelope, producer: producer)
    }

    private func baseCriteria(artifactID: String) -> [FlowEvaluationCriterion] {
        [
            FlowEvaluationCriterion(
                criterionID: "drc-gate-status",
                channelID: "drc-gate-status",
                comparator: .equal,
                target: .text(FlowGateStatus.passed.rawValue)
            ),
            FlowEvaluationCriterion(
                criterionID: "drc-active-violation-count",
                channelID: "drc-active-violation-count",
                comparator: .equal,
                target: .scalar(0)
            ),
            FlowEvaluationCriterion(
                criterionID: "drc-unused-waiver-count",
                channelID: "drc-unused-waiver-count",
                comparator: .equal,
                target: .scalar(0),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "drc-tool-evidence",
                channelID: "drc-tool-evidence-count",
                comparator: .greaterThanOrEqual,
                target: .scalar(1),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "drc-calibration",
                channelID: "drc-qualified-calibration",
                comparator: .equal,
                target: .boolean(true),
                required: false
            ),
            FlowEvaluationCriterion(
                criterionID: "drc-summary-artifact",
                channelID: "drc-summary-artifact-present",
                comparator: .equal,
                target: .boolean(true),
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
        ]
    }

    private func bucketCriteria(summary: DRCRunSummaryReport) -> [FlowEvaluationCriterion] {
        summary.summary.violationBuckets.enumerated().map { index, bucket in
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
        summary: DRCRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        toolEvidenceCount: Int,
        hasQualifiedEvidence: Bool,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        [
            FlowObservationChannel(
                channelID: "drc-summary-artifact-present",
                status: .observed,
                value: .boolean(true),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-gate-status",
                status: .observed,
                value: .text(gateStatus.rawValue),
                sourceArtifactIDs: [artifactID],
                confidence: confidence,
                context: FlowEvaluationContext(gateID: "drc")
            ),
            FlowObservationChannel(
                channelID: "drc-diagnostic-count",
                status: .observed,
                value: .scalar(Double(diagnostics.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-tool-evidence-count",
                status: toolEvidenceCount > 0 ? .observed : .missing,
                value: .scalar(Double(toolEvidenceCount)),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-qualified-calibration",
                status: hasQualifiedEvidence ? .observed : .uncalibrated,
                value: .boolean(hasQualifiedEvidence),
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-completed",
                status: .observed,
                value: .boolean(summary.summary.completed),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-passed",
                status: .observed,
                value: .boolean(summary.summary.passed),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-active-violation-count",
                status: .observed,
                value: .scalar(Double(summary.summary.activeViolationCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-waived-violation-count",
                status: .observed,
                value: .scalar(Double(summary.summary.waivedViolationCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-violation-bucket-count",
                status: .observed,
                value: .scalar(Double(summary.summary.violationBuckets.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-unused-waiver-count",
                status: .observed,
                value: .scalar(Double(summary.summary.unusedWaiverIDs.count)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-info-diagnostic-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.infoCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-warning-diagnostic-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.warningCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-error-diagnostic-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.errorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
            FlowObservationChannel(
                channelID: "drc-waived-error-count",
                status: .observed,
                value: .scalar(Double(summary.summary.diagnosticSummary.waivedErrorCount)),
                sourceArtifactIDs: [artifactID],
                confidence: confidence
            ),
        ]
    }

    private func bucketObservationChannels(
        summary: DRCRunSummaryReport,
        artifactID: String,
        confidence: FlowEvidenceConfidence
    ) -> [FlowObservationChannel] {
        summary.summary.violationBuckets.enumerated().flatMap { index, bucket in
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
                    label: "\(bucketLabel(bucket)) waived",
                    status: .observed,
                    value: .scalar(Double(bucket.waivedCount)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-max-measured",
                    label: "\(bucketLabel(bucket)) max measured",
                    status: bucket.maxMeasured == nil ? .missing : .observed,
                    value: bucket.maxMeasured.map { .scalar($0) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-required",
                    label: "\(bucketLabel(bucket)) required",
                    status: bucket.required == nil ? .missing : .observed,
                    value: bucket.required.map { .scalar($0) },
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-related-shape-count",
                    status: .observed,
                    value: .scalar(Double(bucket.relatedShapeIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-related-net-count",
                    status: .observed,
                    value: .scalar(Double(bucket.relatedNetIDs.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
                FlowObservationChannel(
                    channelID: "\(baseID)-suggested-fix-count",
                    status: .observed,
                    value: .scalar(Double(bucket.suggestedFixes.count)),
                    sourceArtifactIDs: [artifactID],
                    confidence: confidence,
                    context: context
                ),
            ]
        }
    }

    private func baseChannelResults(
        summary: DRCRunSummaryReport,
        artifactID: String,
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic],
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                criterionID: "drc-gate-status",
                channelID: "drc-gate-status",
                status: evaluationStatus(from: gateStatus),
                observedValue: .text(gateStatus.rawValue),
                residual: gateStatus == .passed ? 0 : 1,
                likelihood: likelihood(from: gateStatus),
                confidence: confidence,
                diagnostics: diagnostics.map(runActionDiagnostic)
            ),
            FlowEvaluationChannelResult(
                criterionID: "drc-summary-artifact",
                channelID: "drc-summary-artifact-present",
                status: .accepted,
                observedValue: .boolean(true),
                residual: 0,
                likelihood: 1,
                confidence: confidence,
                context: FlowEvaluationContext(artifactID: artifactID)
            ),
            FlowEvaluationChannelResult(
                criterionID: "drc-active-violation-count",
                channelID: "drc-active-violation-count",
                status: countStatus(summary.summary.activeViolationCount),
                observedValue: .scalar(Double(summary.summary.activeViolationCount)),
                residual: Double(summary.summary.activeViolationCount),
                likelihood: countLikelihood(summary.summary.activeViolationCount),
                confidence: confidence
            ),
            FlowEvaluationChannelResult(
                criterionID: "drc-unused-waiver-count",
                channelID: "drc-unused-waiver-count",
                status: summary.summary.unusedWaiverIDs.isEmpty ? .accepted : .needsHumanReview,
                observedValue: .scalar(Double(summary.summary.unusedWaiverIDs.count)),
                residual: Double(summary.summary.unusedWaiverIDs.count),
                likelihood: countLikelihood(summary.summary.unusedWaiverIDs.count),
                confidence: confidence
            ),
        ]
    }

    private func bucketChannelResults(
        summary: DRCRunSummaryReport,
        confidence: FlowEvidenceConfidence
    ) -> [FlowEvaluationChannelResult] {
        summary.summary.violationBuckets.enumerated().map { index, bucket in
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus,
        confidence: FlowEvidenceConfidence
    ) -> [FlowFeedbackSignal] {
        var signals: [FlowFeedbackSignal] = []
        let activeBuckets = summary.summary.violationBuckets.filter { $0.activeCount > 0 }

        if gateStatus == .passed && activeBuckets.isEmpty {
            signals.append(
                FlowFeedbackSignal(
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
            return FlowFeedbackSignal(
                signalID: "\(baseID)-repair-feedback",
                sourceEvaluationID: "\(artifactID)-evaluation",
                channelID: "\(baseID)-active-count",
                routingLevel: .localSurface,
                severity: .error,
                summary: "DRC rule \(bucketLabel(bucket)) has \(bucket.activeCount) active violation(s).",
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
                    channelID: "drc-unused-waiver-count",
                    routingLevel: .localSurface,
                    severity: .warning,
                    summary: "DRC summary contains unused waiver IDs.",
                    residual: Double(summary.summary.unusedWaiverIDs.count),
                    affectedArtifactIDs: [artifactID],
                    suggestedActions: ["inspect-drc-waivers", "remove-stale-waivers"],
                    confidence: confidence
                )
            )
        }

        if gateStatus != .passed && activeBuckets.isEmpty {
            signals.append(
                FlowFeedbackSignal(
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
                FlowFeedbackSignal(
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

    private func hasQualifiedEvidence(
        context: FlowExecutionContext,
        toolID: String,
        producer: ProducerIdentity
    ) -> Bool {
        guard let descriptor = context.toolRegistry.descriptor(toolID: toolID),
              descriptor.trustProfile.level >= .corpusChecked,
              context.healthResults[toolID]?.status == .passed,
              let qualification = descriptor.trustProfile.processQualification,
              qualification.toolID == toolID,
              qualification.isQualified(at: Date()),
              qualification.scope.implementationID == producer.identifier,
              qualification.scope.toolVersion == producer.version,
              let build = producer.build,
              qualification.scope.binaryDigest.caseInsensitiveCompare(build) == .orderedSame else {
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
        summary: DRCRunSummaryReport,
        gateStatus: FlowGateStatus
    ) -> FlowEvaluationStatus {
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

    private func bucketContext(
        index: Int,
        bucket: DRCViolationBucketSummary
    ) -> FlowEvaluationContext {
        FlowEvaluationContext(
            kind: bucket.kind,
            layer: bucket.layer,
            ruleID: bucket.ruleID,
            requiredValue: bucket.required,
            bucketIndex: index,
            activeCount: bucket.activeCount,
            waivedCount: bucket.waivedCount,
            relatedShapeIDs: bucket.relatedShapeIDs,
            relatedNetIDs: bucket.relatedNetIDs,
            suggestedActions: bucket.suggestedFixes,
            maximumMeasuredValue: bucket.maxMeasured,
            region: bucket.representativeRegion.map {
                FlowEvaluationContext.Region(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
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
