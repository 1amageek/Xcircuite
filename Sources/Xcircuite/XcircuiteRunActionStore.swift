import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    public func appendRunAction(_ record: FlowRunActionRecord) async throws {
        try await FlowRunLedgerCoordinator(persistence: self).update(runID: record.runID) { ledger in
            ledger.actions.append(record)
        }
    }

    public func loadRunActions(runID: String) async throws -> [FlowRunActionRecord] {
        try await loadRunLedger(runID: runID).actions
    }

    public func loadSuggestedCommandSelections(
        runID: String
    ) async throws -> [FlowSuggestedCommandSelection] {
        var selections: [FlowSuggestedCommandSelection] = []
        for record in try await loadRunActions(runID: runID) {
            if let selection = try FlowSuggestedCommandSelection(record: record) {
                selections.append(selection)
            }
        }
        return selections
    }

    public func loadLatestSuggestedCommandSelection(
        runID: String
    ) async throws -> FlowSuggestedCommandSelection? {
        try await loadSuggestedCommandSelections(runID: runID).last
    }
}
