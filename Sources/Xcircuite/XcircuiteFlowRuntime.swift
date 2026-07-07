import DesignFlowKernel
import Foundation
import ToolQualification

public struct XcircuiteFlowRuntime: Sendable {
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]
    private let executors: [any FlowStageExecutor]
    private let toolchainProfile: XcircuiteFlowToolchainProfile?
    private let orchestrator: DefaultFlowOrchestrator
    private let resumer: DefaultFlowRunResumer
    private let planningArtifactStore: XcircuitePlanningArtifactStore
    private let toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore

    public init(
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil,
        orchestrator: DefaultFlowOrchestrator = DefaultFlowOrchestrator(),
        resumer: DefaultFlowRunResumer = DefaultFlowRunResumer(),
        planningArtifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore =
            XcircuiteFlowToolchainProfileArtifactStore()
    ) {
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
        self.executors = executors
        self.toolchainProfile = toolchainProfile
        self.orchestrator = orchestrator
        self.resumer = resumer
        self.planningArtifactStore = planningArtifactStore
        self.toolchainProfileArtifactStore = toolchainProfileArtifactStore
    }

    public init(
        descriptors: [ToolDescriptor],
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil,
        orchestrator: DefaultFlowOrchestrator = DefaultFlowOrchestrator(),
        resumer: DefaultFlowRunResumer = DefaultFlowRunResumer(),
        planningArtifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore =
            XcircuiteFlowToolchainProfileArtifactStore()
    ) {
        self.init(
            toolRegistry: ToolRegistry(descriptors: descriptors),
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: toolchainProfile,
            orchestrator: orchestrator,
            resumer: resumer,
            planningArtifactStore: planningArtifactStore,
            toolchainProfileArtifactStore: toolchainProfileArtifactStore
        )
    }

    public func run(request: FlowOperationRequest) async throws -> FlowRunResult {
        let operationRequest = requestWithToolchainProfile(request)
        let result = try await orchestrator.run(
            request: operationRequest,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors
        )
        try persistToolchainProfileIfNeeded(
            runID: operationRequest.runID,
            projectRoot: operationRequest.projectRoot
        )
        try planningArtifactStore.persistActionDomainSnapshot(
            runID: operationRequest.runID,
            projectRoot: operationRequest.projectRoot
        )
        return result
    }

    public func resume(request: FlowRunResumeRequest) async throws -> FlowRunResumeResult {
        let profileRecord = toolchainProfileRecord(runID: request.runID)
        let result = try await resumer.resumeRun(
            request: request,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: profileRecord
        )
        try persistToolchainProfileIfNeeded(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        try planningArtifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        let summary = try DefaultFlowRunLedgerInspector().inspectRun(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        return FlowRunResumeResult(result: result.result, summary: summary)
    }

    private func requestWithToolchainProfile(_ request: FlowOperationRequest) -> FlowOperationRequest {
        guard let profileRecord = toolchainProfileRecord(runID: request.runID) else {
            return request
        }
        var operationRequest = request
        operationRequest.toolchainProfile = profileRecord
        return operationRequest
    }

    private func toolchainProfileRecord(runID: String) -> FlowToolchainProfileRecord? {
        guard let toolchainProfile else {
            return nil
        }
        return toolchainProfile.flowToolchainRecord(
            profileArtifactPath: XcircuiteFlowToolchainProfileArtifactStore.profileArtifactPath(runID: runID)
        )
    }

    private func persistToolchainProfileIfNeeded(runID: String, projectRoot: URL) throws {
        guard let toolchainProfile else {
            return
        }
        try toolchainProfileArtifactStore.persistProfile(
            toolchainProfile,
            runID: runID,
            projectRoot: projectRoot
        )
    }
}
