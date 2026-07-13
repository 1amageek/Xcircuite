import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanRiskApprovalRecorder: Sendable {
    private let packageStore: XcircuitePackageStore

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore()
    ) {
        self.packageStore = packageStore
    }

    public func recordApproval(
        request: XcircuiteCandidatePlanRiskApprovalRequest,
        projectRoot: URL
    ) throws -> XcircuiteCandidatePlanRiskApprovalResult {
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)
        try validator.validate(request.approvalID, kind: .stageID)

        let approval = XcircuiteApprovalRecord(
            runID: request.runID,
            stageID: request.approvalID,
            verdict: request.verdict,
            reviewer: request.reviewer,
            reviewerKind: request.reviewerKind,
            note: request.note,
            createdAt: request.decidedAt
        )
        let approvalPath = "\(XcircuitePackage.directoryName)/runs/\(request.runID)/approvals/\(request.approvalID).json"
        var approvalArtifact = try packageStore.writeApprovalArtifact(approval, inProjectAt: projectRoot)
        approvalArtifact.artifactID = "planning-approval-\(request.approvalID)"
        try packageStore.upsertRunArtifact(
            approvalArtifact,
            runID: request.runID,
            inProjectAt: projectRoot
        )
        try packageStore.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "\(request.runID)-\(request.approvalID)-approval",
                runID: request.runID,
                stageID: request.approvalID,
                actor: XcircuiteRunActionActor(kind: request.reviewerKind, identifier: request.reviewer),
                actionKind: "planning.approve-candidate-plan-risk",
                status: request.verdict == .approved ? .succeeded : .failed,
                outputs: [approvalArtifact],
                diagnostics: [
                    XcircuiteRunActionDiagnostic(
                        severity: request.verdict == .approved ? .info : .warning,
                        code: request.verdict == .approved ? "risk-approval-recorded" : "risk-approval-rejected",
                        message: "Recorded \(request.verdict.rawValue) decision for planning risk approval \(request.approvalID)."
                    ),
                ]
            ),
            inProjectAt: projectRoot
        )

        return XcircuiteCandidatePlanRiskApprovalResult(
            status: request.verdict.rawValue,
            runID: request.runID,
            approvalID: request.approvalID,
            approvalPath: approvalPath,
            approval: approval,
            approvalArtifact: try requireFoundationArtifactReference(
                approvalArtifact,
                field: "risk-approval"
            ),
            nextActions: ["verify-candidate-plan", "execute-candidate-plan"]
        )
    }
}
