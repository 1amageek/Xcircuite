import Foundation
import DesignFlowKernel

struct FlowExecutionCancellationProbe {
    static func make(context: FlowExecutionContext) -> @Sendable () async throws -> Bool {
        make(runID: context.runID, projectRoot: context.projectRoot)
    }

    static func make(
        runID: String,
        projectRoot: URL,
        progressStore: FlowRunProgressStore = FlowRunProgressStore()
    ) -> @Sendable () async throws -> Bool {
        {
            try progressStore.loadCancellationRequest(
                runID: runID,
                projectRoot: projectRoot
            ) != nil
        }
    }
}
