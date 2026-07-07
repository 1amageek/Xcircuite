import DesignFlowKernel
import Foundation
import ToolQualification

public enum XcircuiteFlowRuntimeFactory {
    public static func make(
        descriptors: [ToolDescriptor],
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) -> XcircuiteFlowRuntime {
        XcircuiteFlowRuntime(
            descriptors: descriptors,
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: toolchainProfile
        )
    }

    public static func makeHealthyInProcessRuntime(
        executors: [any FlowStageExecutor],
        descriptors: [ToolDescriptor],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) -> XcircuiteFlowRuntime {
        let healthResults = Dictionary(
            uniqueKeysWithValues: descriptors.map {
                ($0.toolID, ToolHealthCheckResult(toolID: $0.toolID, status: .passed))
            }
        )
        return XcircuiteFlowRuntime(
            descriptors: descriptors,
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: toolchainProfile
        )
    }
}
