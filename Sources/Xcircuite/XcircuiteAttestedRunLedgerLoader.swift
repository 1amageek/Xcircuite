import DesignFlowKernel

public struct XcircuiteAttestedRunLedgerLoader: FlowRunLedgerLoading, Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    public func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        try await workspaceStore.loadAttestedRunLedger(runID: runID)
    }
}
