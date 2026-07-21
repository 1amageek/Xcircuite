import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct XcircuiteFlowRunArtifactPreparer: FlowRunArtifactPreparing, Sendable {
    private let projectRoot: URL
    private let toolchainProfile: XcircuiteFlowToolchainProfile?
    private let planningArtifactStore: XcircuitePlanningArtifactStore
    private let toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore

    public init(
        projectRoot: URL,
        toolchainProfile: XcircuiteFlowToolchainProfile?,
        planningArtifactStore: XcircuitePlanningArtifactStore,
        toolchainProfileArtifactStore: XcircuiteFlowToolchainProfileArtifactStore
    ) {
        self.projectRoot = projectRoot
        self.toolchainProfile = toolchainProfile
        self.planningArtifactStore = planningArtifactStore
        self.toolchainProfileArtifactStore = toolchainProfileArtifactStore
    }

    public func prepareArtifacts(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> [ArtifactReference] {
        _ = workspaceID
        var references: [ArtifactReference] = []
        if let toolchainProfile {
            references.append(try await toolchainProfileArtifactStore.persistProfile(
                toolchainProfile,
                runID: runID,
                projectRoot: projectRoot
            ))
        }
        references.append(try await planningArtifactStore.persistActionDomainSnapshot(
            runID: runID,
            projectRoot: projectRoot
        ))
        return references
    }
}
