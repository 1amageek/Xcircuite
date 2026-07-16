import DesignFlowKernel
import Foundation
import ToolQualification

public enum XcircuiteFlowRuntimeFactory {
    public static func make(
        descriptors: [ToolDescriptor],
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        projectRoot: URL,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) throws -> XcircuiteFlowRuntime {
        try XcircuiteFlowRuntime(
            descriptors: descriptors,
            healthResults: healthResults,
            executors: executors,
            workspaceStore: XcircuiteWorkspaceStore(projectRoot: projectRoot),
            toolchainProfile: toolchainProfile
        )
    }

    public static func makeHealthyInProcessRuntime(
        executors: [any FlowStageExecutor],
        descriptors: [ToolDescriptor],
        projectRoot: URL,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) throws -> XcircuiteFlowRuntime {
        let healthResults = Dictionary(
            uniqueKeysWithValues: descriptors.map {
                ($0.toolID, ToolHealthCheckResult(toolID: $0.toolID, status: .passed))
            }
        )
        return try XcircuiteFlowRuntime(
            descriptors: descriptors,
            healthResults: healthResults,
            executors: executors,
            workspaceStore: XcircuiteWorkspaceStore(projectRoot: projectRoot),
            toolchainProfile: toolchainProfile
        )
    }
}
