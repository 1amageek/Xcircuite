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

        let ledger = try await workspaceStore.loadRunLedger(runID: request.runID)
        let currentPlanReference = try requiredArtifact(
            id: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            in: ledger
        )
        let candidatePlan: XcircuiteCandidatePlan = try await decodedArtifact(
            currentPlanReference,
            as: XcircuiteCandidatePlan.self
        )
        let verification = try await requiredVerificationArtifact(
            for: candidatePlan,
            in: ledger
        )
        let planVerification: XcircuitePlanVerification = try await decodedArtifact(
            verification,
            as: XcircuitePlanVerification.self
        )
        let reviewedPlanReference = planVerification.candidatePlanRef
        let reviewedPlan: XcircuiteCandidatePlan = try await decodedArtifact(
            reviewedPlanReference,
            as: XcircuiteCandidatePlan.self
        )
        guard reviewedPlan == candidatePlan else {
            throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                "The retained verification does not contain the current candidate plan bytes."
            )
        }
        try validateEvidence(
            plan: candidatePlan,
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

    private func requiredArtifact(id: String, in ledger: FlowRunLedger) throws -> ArtifactReference {
        let matches = ledger.artifacts.filter { $0.id.rawValue == id }
        guard matches.count == 1, let artifact = matches.first else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "Approval evidence requires exactly one \(id) artifact."
            )
        }
        return artifact
    }

    private func requiredVerificationArtifact(
        for candidatePlan: XcircuiteCandidatePlan,
        in ledger: FlowRunLedger
    ) async throws -> ArtifactReference {
        var matches: [ArtifactReference] = []
        for reference in ledger.artifacts where
            reference.id.rawValue == XcircuitePlanningArtifactStore.planVerificationArtifactID {
            let verification: XcircuitePlanVerification = try await decodedArtifact(
                reference,
                as: XcircuitePlanVerification.self
            )
            if verification.runID == candidatePlan.runID,
               verification.planID == candidatePlan.planID,
               verification.problemID == candidatePlan.problemID {
                matches.append(reference)
            }
        }
        guard !matches.isEmpty else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "Approval evidence requires plan verification bound to the current candidate plan."
            )
        }
        guard matches.count > 1 else {
            return matches[0]
        }
        let matchSet = Set(matches)
        for action in ledger.actions.reversed() where
            action.actionKind == "planning.verify-candidate-plan" {
            if let reference = action.outputs.first(where: matchSet.contains) {
                return reference
            }
        }
        throw XcircuiteRuntimeError.invalidConfiguration(
            "Approval evidence has multiple plan verifications without an ordered action binding."
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
