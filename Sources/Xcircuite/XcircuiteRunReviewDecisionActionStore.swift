import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    @discardableResult
    public func appendReviewDecisionAction(
        _ request: FlowRunReviewDecisionRequest
    ) async throws -> FlowRunActionRecord {
        let validator = FlowIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)
        if let stageID = request.stageID {
            try validator.validate(stageID, kind: .stageID)
        }

        let record = FlowRunActionRecord(
            actionID: request.actionID,
            runID: request.runID,
            stageID: request.stageID,
            actor: request.actor,
            actionKind: request.decisionKind.rawValue,
            status: request.status,
            inputs: request.inputs,
            outputs: request.outputs,
            diagnostics: request.diagnostics,
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: request.decisionKind,
                    decision: request.decision,
                    targetID: request.targetID,
                    targetPath: request.targetPath,
                    reason: request.reason
                )
            ),
            createdAt: request.createdAt
        )
        try await appendRunAction(record)
        return record
    }

    public func loadReviewDecisionActions(
        runID: String
    ) async throws -> [FlowRunReviewDecision] {
        var decisions: [FlowRunReviewDecision] = []
        for record in try await loadRunActions(runID: runID) {
            if let decision = try FlowRunReviewDecision(record: record) {
                decisions.append(decision)
            }
        }
        return decisions
    }

    public func loadLatestReviewDecisionAction(
        runID: String,
        decisionKind: FlowRunReviewDecisionKind? = nil,
        targetID: String? = nil
    ) async throws -> FlowRunReviewDecision? {
        try await loadReviewDecisionActions(runID: runID)
            .last { decision in
                (decisionKind == nil || decision.decisionKind == decisionKind)
                    && (targetID == nil || decision.targetID == targetID)
            }
    }
}
