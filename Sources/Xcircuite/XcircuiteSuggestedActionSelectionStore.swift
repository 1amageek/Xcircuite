import DesignFlowKernel
import Foundation

/// Project-runtime storage required to resolve reviewed semantic actions.
public protocol XcircuiteSuggestedActionSelectionStore: Sendable {
    var projectRoot: URL { get }

    func loadSuggestedActionSelections(
        runID: String
    ) async throws -> [FlowRunSuggestedActionSelection]
}

extension XcircuiteWorkspaceStore: XcircuiteSuggestedActionSelectionStore {}
