import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    public func appendRunAction(_ record: FlowRunActionRecord) async throws {
        _ = try appendRunActionAtomically(record)
    }

    public func loadRunActions(runID: String) async throws -> [FlowRunActionRecord] {
        try await loadRunLedger(runID: runID).actions
    }

    public func loadSuggestedActionSelections(
        runID: String
    ) async throws -> [FlowRunSuggestedActionSelection] {
        try await loadRunLedger(runID: runID).suggestedActionSelections
    }
}
