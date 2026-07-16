import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct XcircuiteCandidatePlanRiskApprovalRecorder: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    public func recordApproval(
        request: XcircuiteCandidatePlanRiskApprovalRequest,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanRiskApprovalResult {
        let validator = FlowIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)
        try validator.validate(request.approvalID, kind: .stageID)

        let ledger = try await workspaceStore.loadRunLedger(runID: request.runID)
        let plan = try requiredArtifact(
            id: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            in: ledger
        )
        _ = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(runID: request.runID),
            projectRoot: projectRoot
        )
        let verifiedLedger = try await workspaceStore.loadRunLedger(runID: request.runID)
        let verification = try requiredArtifact(
            id: XcircuitePlanningArtifactStore.planVerificationArtifactID,
            in: verifiedLedger
        )
        let approval = FlowApprovalRecord(
            runID: request.runID,
            stageID: request.approvalID,
            verdict: request.verdict,
            reviewer: request.reviewer,
            reviewerKind: request.reviewerKind,
            note: request.note,
            createdAt: request.decidedAt,
            evidence: FlowApprovalEvidenceBinding(plan: plan, stageResult: verification)
        )
        let approvalPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(request.runID)/approvals/\(request.approvalID).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let approvalArtifact = try await workspaceStore.persistArtifact(
            content: encoder.encode(approval),
            id: ArtifactID(rawValue: "planning-approval-\(request.approvalID)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: approvalPath),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            runID: request.runID,
            mode: .immutable
        )
        try await FlowRunLedgerCoordinator(persistence: workspaceStore).update(runID: request.runID) { ledger in
            ledger.approvals.removeAll { $0.stageID == request.approvalID }
            ledger.approvals.append(approval)
            ledger.actions.append(
                FlowRunActionRecord(
                    actionID: "\(request.runID)-\(request.approvalID)-approval",
                    runID: request.runID,
                    stageID: request.approvalID,
                    actor: FlowRunActor(kind: request.reviewerKind, identifier: request.reviewer),
                    actionKind: "planning.approve-candidate-plan-risk",
                    status: request.verdict == .approved ? .succeeded : .failed,
                    inputs: [plan, verification],
                    outputs: [approvalArtifact],
                    diagnostics: [
                        FlowRunDiagnostic(
                            severity: request.verdict == .approved ? .info : .warning,
                            code: request.verdict == .approved ? "risk-approval-recorded" : "risk-approval-rejected",
                            message: "Recorded \(request.verdict.rawValue) decision for planning risk approval \(request.approvalID)."
                        ),
                    ]
                )
            )
        }

        return XcircuiteCandidatePlanRiskApprovalResult(
            status: request.verdict.rawValue,
            runID: request.runID,
            approvalID: request.approvalID,
            approvalPath: approvalPath,
            approval: approval,
            approvalArtifact: approvalArtifact,
            nextActions: ["verify-candidate-plan", "execute-candidate-plan"]
        )
    }

    private func requiredArtifact(id: String, in ledger: FlowRunLedger) throws -> ArtifactReference {
        let matches = ledger.artifacts.filter { $0.id.rawValue == id }
        guard matches.count == 1, let artifact = matches.first else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "Approval evidence requires exactly one \(id) artifact."
            )
        }
        return artifact
    }
}
