import DesignFlowKernel
import Foundation

extension FlowExecutionContext {
    func xcircuiteProjectRoot() throws -> URL {
        try xcircuiteWorkspaceStore().projectRoot
    }

    func xcircuiteRunDirectory() throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: xcircuiteProjectRoot())
            .runDirectoryURL(for: runID)
    }

    private func xcircuiteWorkspaceStore() throws -> XcircuiteWorkspaceStore {
        guard let store = infrastructure as? XcircuiteWorkspaceStore else {
            throw XcircuiteRuntimeError.invalidFlowInfrastructure(
                actualType: String(reflecting: type(of: infrastructure))
            )
        }
        return store
    }
}
