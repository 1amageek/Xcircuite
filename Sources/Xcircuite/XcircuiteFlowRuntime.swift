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
    private let workspaceStore: XcircuiteWorkspaceStore

    public init(
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        workspaceStore: XcircuiteWorkspaceStore,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil,
        orchestrator: DefaultFlowOrchestrator? = nil,
        resumer: DefaultFlowRunResumer? = nil,
        planningArtifactStore: XcircuitePlanningArtifactStore? = nil,
        toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore? = nil
    ) {
        let progressStore = FlowRunProgressStore(persistence: workspaceStore)
        let resolvedOrchestrator = orchestrator ?? DefaultFlowOrchestrator(
            infrastructure: workspaceStore,
            ledgerPersistence: workspaceStore,
            progressStore: progressStore
        )
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        let inspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
        self.executors = executors
        self.toolchainProfile = toolchainProfile
        self.orchestrator = resolvedOrchestrator
        self.resumer = resumer ?? DefaultFlowRunResumer(
            loader: workspaceStore,
            orchestrator: resolvedOrchestrator,
            inspector: inspector,
            artifactPersistence: workspaceStore
        )
        self.planningArtifactStore = planningArtifactStore
            ?? XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        self.toolchainProfileArtifactStore = toolchainProfileArtifactStore
            ?? XcircuiteFlowToolchainProfileArtifactStore(workspaceStore: workspaceStore)
        self.workspaceStore = workspaceStore
    }

    public init(
        descriptors: [ToolDescriptor],
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        workspaceStore: XcircuiteWorkspaceStore,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil,
        orchestrator: DefaultFlowOrchestrator? = nil,
        resumer: DefaultFlowRunResumer? = nil,
        planningArtifactStore: XcircuitePlanningArtifactStore? = nil,
        toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore? = nil
    ) {
        self.init(
            toolRegistry: ToolRegistry(descriptors: descriptors),
            healthResults: healthResults,
            executors: executors,
            workspaceStore: workspaceStore,
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
        try await persistToolchainProfileIfNeeded(
            runID: operationRequest.runID,
            projectRoot: operationRequest.projectRoot
        )
        _ = try await planningArtifactStore.persistActionDomainSnapshot(
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
        try await persistToolchainProfileIfNeeded(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        _ = try await planningArtifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        let reviewBundler = DefaultFlowRunReviewBundler(loader: workspaceStore, persistence: workspaceStore)
        let summary = try await DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler).inspectRun(
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

    private func persistToolchainProfileIfNeeded(runID: String, projectRoot: URL) async throws {
        guard let toolchainProfile else {
            return
        }
        try await toolchainProfileArtifactStore.persistProfile(
            toolchainProfile,
            runID: runID,
            projectRoot: projectRoot
        )
    }
}
