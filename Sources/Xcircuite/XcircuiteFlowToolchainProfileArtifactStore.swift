import Foundation
import DesignFlowKernel

public struct XcircuiteFlowToolchainProfileArtifactStore: Sendable {
    public static let artifactID = "flow-toolchain-profile"
    public static let relativePath = "toolchain-profile.json"

    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    public static func profileArtifactPath(runID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/\(relativePath)"
    }

    @discardableResult
    public func persistProfile(
        _ profile: XcircuiteFlowToolchainProfile,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        guard workspaceStore.projectRoot == projectRoot.standardizedFileURL else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(projectRoot.path(percentEncoded: false))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await workspaceStore.persistArtifact(
            content: encoder.encode(profile),
            id: try ArtifactID(rawValue: Self.artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: Self.profileArtifactPath(runID: runID)),
                role: .output,
                kind: .technology,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }
}
import CircuiteFoundation
