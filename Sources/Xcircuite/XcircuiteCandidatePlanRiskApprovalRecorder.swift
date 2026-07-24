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
        _ = projectRoot
        let validator = FlowIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)
        try validator.validate(request.approvalID, kind: .stageID)

        let ledger = try await workspaceStore.loadAttestedRunLedger(runID: request.runID)
        let (verification, planVerification) = try await currentVerification(in: ledger)
        let reviewedPlanReference = planVerification.candidatePlanRef
        let reviewedPlan: XcircuiteCandidatePlan = try await decodedArtifact(
            reviewedPlanReference,
            as: XcircuiteCandidatePlan.self
        )
        guard reviewedPlan.runID == request.runID,
              reviewedPlan.planID == planVerification.planID,
              reviewedPlan.problemID == planVerification.problemID,
              planVerification.artifactRefs.contains(reviewedPlanReference) else {
            throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                "The retained verification does not bind its reviewed candidate plan."
            )
        }
        try validateEvidence(
            plan: reviewedPlan,
            planReference: reviewedPlanReference,
            verification: planVerification,
            request: request
        )
        let approval = FlowApprovalRecord(
            runID: request.runID,
            stageID: request.approvalID,
            verdict: request.verdict,
            reviewer: request.reviewer,
            reviewerKind: request.reviewerKind,
            note: request.note,
            createdAt: request.decidedAt,
            evidence: FlowApprovalEvidenceBinding(
                plan: reviewedPlanReference,
                stageResult: verification
            )
        )
        let approvalPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(request.runID)/approvals/\(request.approvalID).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let approvalContent = try encoder.encode(approval)
        let approvalArtifact = ArtifactReference(
            id: try ArtifactID(rawValue: "approval-\(request.approvalID)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: approvalPath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: approvalContent, using: .sha256),
            byteCount: UInt64(approvalContent.count)
        )
        let action = FlowRunActionRecord(
            actionID: "\(request.runID)-\(request.approvalID)-approval",
            runID: request.runID,
            stageID: request.approvalID,
            actor: FlowRunActor(kind: request.reviewerKind, identifier: request.reviewer),
            actionKind: "planning.approve-candidate-plan-risk",
            status: request.verdict == .approved ? .succeeded : .failed,
            inputs: [reviewedPlanReference, verification],
            outputs: [approvalArtifact],
            diagnostics: [
                FlowRunDiagnostic(
                    severity: request.verdict == .approved ? .info : .warning,
                    code: request.verdict == .approved ? "risk-approval-recorded" : "risk-approval-rejected",
                    message: "Recorded \(request.verdict.rawValue) decision for planning risk approval \(request.approvalID)."
                ),
            ],
            createdAt: request.decidedAt
        )
        _ = try await workspaceStore.appendApprovalArtifact(
            content: approvalContent,
            reference: approvalArtifact,
            approval: approval,
            action: action
        )

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

    private func currentVerification(
        in ledger: FlowRunLedger
    ) async throws -> (ArtifactReference, XcircuitePlanVerification) {
        let retainedReferences = Set(ledger.artifacts + ledger.actions.flatMap(\.outputs))
        for action in ledger.actions.reversed() where
            action.actionKind == "planning.verify-candidate-plan" {
            for reference in action.outputs where
                reference.id.rawValue == XcircuitePlanningArtifactStore.planVerificationArtifactID
                    && retainedReferences.contains(reference) {
                let verification: XcircuitePlanVerification = try await decodedArtifact(
                    reference,
                    as: XcircuitePlanVerification.self
                )
                guard verification.runID == ledger.runID,
                      action.runID == ledger.runID,
                      action.inputs == [verification.candidatePlanRef] else {
                    continue
                }
                return (reference, verification)
            }
        }
        throw XcircuiteRuntimeError.invalidConfiguration(
            "Approval evidence requires an action-bound plan verification."
        )
    }

    private func decodedArtifact<Value: Decodable>(
        _ reference: ArtifactReference,
        as type: Value.Type
    ) async throws -> Value {
        let data = try await workspaceStore.loadArtifactContent(for: reference)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactPayload(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
    }

    private func validateEvidence(
        plan: XcircuiteCandidatePlan,
        planReference: ArtifactReference,
        verification: XcircuitePlanVerification,
        request: XcircuiteCandidatePlanRiskApprovalRequest
    ) throws {
        guard plan.runID == request.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: request.runID,
                actual: plan.runID
            )
        }
        guard verification.runID == request.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: request.runID,
                actual: verification.runID
            )
        }
        guard verification.planID == plan.planID,
              verification.problemID == plan.problemID,
              verification.candidatePlanRef == planReference,
              verification.artifactRefs.contains(planReference) else {
            throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                "The retained verification does not bind the current candidate plan identity."
            )
        }
        guard verification.riskReviews.contains(where: {
            $0.requiredApprovals.contains(request.approvalID)
        }) else {
            throw XcircuiteCandidatePlanVerificationError.approvalRequirementNotFound(
                request.approvalID
            )
        }
    }
}
