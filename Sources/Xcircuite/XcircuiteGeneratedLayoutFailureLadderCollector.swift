import DesignFlowKernel
import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutFailureLadderCollector: Sendable {
    private let ledgerLoader: any FlowRunLedgerLoading
    private let reviewBundler: any FlowRunReviewBundling
    private let workspaceStore: XcircuiteWorkspaceStore
    private let identifierValidator: FlowIdentifierValidator
    private let stageClassifier: XcircuiteGeneratedLayoutSignoffStageClassifier

    public init(
        ledgerLoader: any FlowRunLedgerLoading,
        reviewBundler: any FlowRunReviewBundling,
        workspaceStore: XcircuiteWorkspaceStore,
        identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator(),
        stageClassifier: XcircuiteGeneratedLayoutSignoffStageClassifier = XcircuiteGeneratedLayoutSignoffStageClassifier()
    ) {
        self.ledgerLoader = ledgerLoader
        self.reviewBundler = reviewBundler
        self.workspaceStore = workspaceStore
        self.identifierValidator = identifierValidator
        self.stageClassifier = stageClassifier
    }

    public func collect(
        request: XcircuiteGeneratedLayoutFailureLadderRequest,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutFailureLadderReport {
        try validate(request)
        let ledger = try await ledgerLoader.loadRunLedger(runID: request.runID)
        let bundle = try await reviewBundler.makeReviewBundle(runID: request.runID, projectRoot: projectRoot)
        let stageNodes = makeStageNodes(
            request: request,
            ledger: ledger,
            bundle: bundle
        )
        guard let firstFailure = stageNodes.first(where: isFailureNode) else {
            throw XcircuiteGeneratedLayoutFailureLadderError.missingFailure(request.runID)
        }
        let markedStageNodes = markFailurePath(stageNodes, firstFailureOrder: firstFailure.order)
        let suggestedActions = makeSuggestedActions(stageNodes: markedStageNodes)
        return makeReport(
            request: request,
            ledger: ledger,
            bundle: bundle,
            stageNodes: markedStageNodes,
            suggestedActions: suggestedActions,
            reportArtifact: nil
        )
    }

    public func collectAndPersist(
        request: XcircuiteGeneratedLayoutFailureLadderRequest,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutFailureLadderReport {
        let reportWithoutSelfRef = try await collect(request: request, projectRoot: projectRoot)
        let reportPath = reportProjectRelativePath(runID: request.runID, ladderID: request.ladderID)
        let reportArtifact = try await workspaceStore.persistProjectJSON(
            reportWithoutSelfRef,
            id: request.ladderID,
            path: reportPath
        )

        var report = reportWithoutSelfRef
        report.reportArtifact = reportArtifact
        return report
    }

    private func validate(_ request: XcircuiteGeneratedLayoutFailureLadderRequest) throws {
        guard request.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutFailureLadderError.unsupportedSchemaVersion(request.schemaVersion)
        }
        try identifierValidator.validate(request.ladderID, kind: .artifactID)
        try identifierValidator.validate(request.runID, kind: .runID)
        for stageID in request.expectedStageFamilies.keys {
            try identifierValidator.validate(stageID, kind: .stageID)
        }
    }

    private func makeStageNodes(
        request: XcircuiteGeneratedLayoutFailureLadderRequest,
        ledger: FlowRunLedger,
        bundle: FlowRunReviewBundle
    ) -> [XcircuiteGeneratedLayoutFailureLadderReport.StageNode] {
        ledger.stages.enumerated().map { offset, stage in
            let artifactRefs = bundle.artifacts
                .filter { $0.stageID == stage.stageID }
                .map(artifactReference)
                .sorted(by: artifactReferenceSortOrder)
            let artifactIssues = bundle.artifacts
                .filter { $0.stageID == stage.stageID }
                .compactMap(artifactIssue)
                .sorted { $0.path < $1.path }
            let diagnostics = stage.diagnostics.map(reportDiagnostic)
            return XcircuiteGeneratedLayoutFailureLadderReport.StageNode(
                stageID: stage.stageID,
                family: request.expectedStageFamilies[stage.stageID] ?? stageClassifier.family(for: stage),
                order: offset,
                status: stage.status,
                isFirstFailure: false,
                isAffectedDownstream: false,
                gates: stage.gates.map(gateNode),
                artifactRefs: artifactRefs,
                artifactIssues: artifactIssues,
                diagnostics: diagnostics,
                attempts: stage.attempts.map(attempt)
            )
        }
    }

    private func markFailurePath(
        _ stageNodes: [XcircuiteGeneratedLayoutFailureLadderReport.StageNode],
        firstFailureOrder: Int
    ) -> [XcircuiteGeneratedLayoutFailureLadderReport.StageNode] {
        stageNodes.map { node in
            var marked = node
            marked.isFirstFailure = node.order == firstFailureOrder
            marked.isAffectedDownstream = node.order > firstFailureOrder
                && (node.status == .blocked || node.status == .skipped || node.status == .failed)
            return marked
        }
    }

    private func makeReport(
        request: XcircuiteGeneratedLayoutFailureLadderRequest,
        ledger: FlowRunLedger,
        bundle: FlowRunReviewBundle,
        stageNodes: [XcircuiteGeneratedLayoutFailureLadderReport.StageNode],
        suggestedActions: [XcircuiteGeneratedLayoutFailureLadderReport.SuggestedAction],
        reportArtifact: ArtifactReference?
    ) -> XcircuiteGeneratedLayoutFailureLadderReport {
        let firstFailure = stageNodes.first(where: \.isFirstFailure)
        let affectedDownstreamStageIDs = stageNodes
            .filter(\.isAffectedDownstream)
            .map(\.stageID)
        let artifactIssueCount = stageNodes.reduce(0) { $0 + $1.artifactIssues.count }
        let diagnosticCount = stageNodes.reduce(0) { partial, stage in
            partial + stage.diagnostics.count + stage.gates.reduce(0) { $0 + $1.diagnostics.count }
        }
        return XcircuiteGeneratedLayoutFailureLadderReport(
            ladderID: request.ladderID,
            runID: request.runID,
            runStatus: ledger.runResult.status,
            summary: XcircuiteGeneratedLayoutFailureLadderReport.Summary(
                stageCount: stageNodes.count,
                failingStageCount: stageNodes.filter { $0.status == .failed }.count,
                blockedStageCount: stageNodes.filter { $0.status == .blocked }.count,
                skippedStageCount: stageNodes.filter { $0.status == .skipped }.count,
                artifactIssueCount: artifactIssueCount,
                diagnosticCount: diagnosticCount,
                firstFailingStageID: firstFailure?.stageID,
                firstFailingGateID: firstFailure?.gates.first(where: isFailingGate)?.gateID,
                firstFailingFamily: firstFailure?.family,
                affectedDownstreamStageIDs: affectedDownstreamStageIDs,
                suggestedActionCount: suggestedActions.count,
                reviewItemCount: bundle.reviewItems.count,
                approvalCount: bundle.approvals.count
            ),
            stageNodes: stageNodes,
            suggestedActions: suggestedActions,
            reportArtifact: reportArtifact
        )
    }

    private func makeSuggestedActions(
        stageNodes: [XcircuiteGeneratedLayoutFailureLadderReport.StageNode]
    ) -> [XcircuiteGeneratedLayoutFailureLadderReport.SuggestedAction] {
        guard let firstFailure = stageNodes.first(where: \.isFirstFailure) else {
            return []
        }
        var actions: [XcircuiteGeneratedLayoutFailureLadderReport.SuggestedAction] = []
        let evidenceArtifactIDs = firstFailure.artifactRefs.compactMap(\.artifactID).sorted()
        let diagnosticCodes = diagnosticCodes(from: firstFailure)

        if !firstFailure.artifactIssues.isEmpty {
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 0,
                actionKind: "inspect-artifact-integrity",
                rationale: "The first failing stage has missing or mismatched artifact integrity evidence.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        }

        switch firstFailure.family {
        case .layout:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-layout-command-request",
                rationale: "The generated layout stage failed before signoff could consume stable layout artifacts.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 20,
                actionKind: "repair-layout-command",
                rationale: "Regenerate the layout command output before rerunning DRC, LVS, or PEX.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .drc:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-drc-summary",
                rationale: "DRC is the first failing signoff gate and should drive geometry repair candidates.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 20,
                actionKind: "repair-layout-geometry",
                rationale: "Use DRC diagnostics and source layout refs to propose a geometry edit.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .lvs:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-lvs-summary",
                rationale: "LVS is the first failing signoff gate and should drive connectivity or device mapping repair.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 20,
                actionKind: "compare-layout-and-schematic-netlists",
                rationale: "Compare extracted layout connectivity against schematic netlist intent before editing.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .pex:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-pex-summary",
                rationale: "PEX is the first failing signoff gate and should drive extractor or technology input review.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 20,
                actionKind: "review-parasitic-technology-inputs",
                rationale: "Validate parasitic technology inputs before using extracted values for post-layout decisions.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .postLayout:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-post-layout-comparison",
                rationale: "Post-layout comparison failed after signoff artifacts were available.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 20,
                actionKind: "propose-metric-repair",
                rationale: "Use the metric deltas to decide whether sizing, routing, or parasitic mitigation is needed.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .simulation:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-simulation-summary",
                rationale: "Simulation is the first failing gate and should drive electrical metric repair.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        case .other:
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 10,
                actionKind: "inspect-stage-diagnostics",
                rationale: "The first failing stage is not classified into a known generated-layout signoff family.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        }

        if firstFailure.attempts.contains(where: { !$0.shouldRetry && $0.retryReason == .maxAttemptsReached }) {
            actions.append(suggestedAction(
                stage: firstFailure,
                index: actions.count,
                priority: 30,
                actionKind: "inspect-tool-health",
                rationale: "The stage exhausted retry attempts and may require tool health or input readiness review.",
                evidenceArtifactIDs: evidenceArtifactIDs,
                diagnosticCodes: diagnosticCodes
            ))
        }

        return actions.sorted { left, right in
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.actionID < right.actionID
        }
    }

    private func suggestedAction(
        stage: XcircuiteGeneratedLayoutFailureLadderReport.StageNode,
        index: Int,
        priority: Int,
        actionKind: String,
        rationale: String,
        evidenceArtifactIDs: [String],
        diagnosticCodes: [String]
    ) -> XcircuiteGeneratedLayoutFailureLadderReport.SuggestedAction {
        XcircuiteGeneratedLayoutFailureLadderReport.SuggestedAction(
            actionID: "\(stage.stageID).\(index).\(actionKind)",
            stageID: stage.stageID,
            family: stage.family,
            priority: priority,
            actionKind: actionKind,
            rationale: rationale,
            evidenceArtifactIDs: evidenceArtifactIDs,
            diagnosticCodes: diagnosticCodes
        )
    }

    private func isFailureNode(_ node: XcircuiteGeneratedLayoutFailureLadderReport.StageNode) -> Bool {
        node.status == .failed
            || node.status == .blocked
            || node.gates.contains(where: isFailingGate)
            || !node.artifactIssues.isEmpty
    }

    private func isFailingGate(_ gate: XcircuiteGeneratedLayoutFailureLadderReport.GateNode) -> Bool {
        gate.status == .failed || gate.status == .incomplete
    }

    private func gateNode(_ gate: FlowGateResult) -> XcircuiteGeneratedLayoutFailureLadderReport.GateNode {
        XcircuiteGeneratedLayoutFailureLadderReport.GateNode(
            gateID: gate.gateID,
            status: gate.status,
            diagnostics: gate.diagnostics.map(reportDiagnostic)
        )
    }

    private func artifactReference(
        _ artifact: FlowRunReviewArtifact
    ) -> XcircuiteGeneratedLayoutFailureLadderReport.ArtifactSnapshot {
        XcircuiteGeneratedLayoutFailureLadderReport.ArtifactSnapshot(
            role: artifact.purpose.rawValue,
            artifactID: artifact.reference.id.rawValue,
            stageID: artifact.stageID,
            path: artifact.reference.locator.location.value,
            kind: artifact.reference.locator.kind.rawValue,
            format: artifact.reference.locator.format.rawValue,
            sha256: artifact.reference.digest.hexadecimalValue,
            byteCount: Int64(exactly: artifact.reference.byteCount),
            integrityStatus: artifact.integrity?.status.rawValue,
            integrityMessage: artifact.integrity?.message
        )
    }

    private func artifactIssue(
        _ artifact: FlowRunReviewArtifact
    ) -> XcircuiteGeneratedLayoutFailureLadderReport.ArtifactIssue? {
        guard let integrity = artifact.integrity, integrity.status != .verified else {
            return nil
        }
        return XcircuiteGeneratedLayoutFailureLadderReport.ArtifactIssue(
            artifactID: artifact.reference.id.rawValue,
            path: artifact.reference.locator.location.value,
            status: integrity.status.rawValue,
            message: integrity.message
        )
    }

    private func attempt(
        _ attempt: FlowStageAttemptRecord
    ) -> XcircuiteGeneratedLayoutFailureLadderReport.Attempt {
        XcircuiteGeneratedLayoutFailureLadderReport.Attempt(
            attemptIndex: attempt.attemptIndex,
            maxAttempts: attempt.maxAttempts,
            status: attempt.status,
            diagnosticCodes: attempt.diagnosticCodes,
            shouldRetry: attempt.retryDecision.shouldRetry,
            retryReason: attempt.retryDecision.reason,
            matchedDiagnosticCodes: attempt.retryDecision.matchedDiagnosticCodes
        )
    }

    private func reportDiagnostic(_ diagnostic: FlowDiagnostic) -> XcircuiteGeneratedLayoutFailureLadderReport.Diagnostic {
        XcircuiteGeneratedLayoutFailureLadderReport.Diagnostic(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func diagnosticCodes(
        from stage: XcircuiteGeneratedLayoutFailureLadderReport.StageNode
    ) -> [String] {
        Array(Set(
            stage.diagnostics.map(\.code)
                + stage.gates.flatMap { $0.diagnostics.map(\.code) }
                + stage.attempts.flatMap(\.diagnosticCodes)
        )).sorted()
    }

    private func reportProjectRelativePath(runID: String, ladderID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/reports/generated-layout-failure-ladder-\(ladderID).json"
    }

    private func artifactReferenceSortOrder(
        _ left: XcircuiteGeneratedLayoutFailureLadderReport.ArtifactSnapshot,
        _ right: XcircuiteGeneratedLayoutFailureLadderReport.ArtifactSnapshot
    ) -> Bool {
        if left.role != right.role {
            return left.role < right.role
        }
        if left.artifactID != right.artifactID {
            return (left.artifactID ?? "") < (right.artifactID ?? "")
        }
        return left.path < right.path
    }
}
