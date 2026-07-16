import Foundation
import DesignFlowKernel

struct FlowExecutionCancellationProbe {
    static func make(context: FlowExecutionContext) -> @Sendable () async throws -> Bool {
        {
            try await context.loadCancellationRequest() != nil
        }
    }

    static func make(
        runID: String,
        projectRoot: URL
    ) -> @Sendable () async throws -> Bool {
        {
            let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
            return try await store.loadCancellationRequest(runID: runID) != nil
        }
    }
}
