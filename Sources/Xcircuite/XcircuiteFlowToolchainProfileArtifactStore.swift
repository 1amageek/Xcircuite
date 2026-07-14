import Foundation
import DesignFlowKernel

public struct XcircuiteFlowToolchainProfileArtifactStore: Sendable {
    public static let artifactID = "flow-toolchain-profile"
    public static let relativePath = "toolchain-profile.json"

    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore()) {
        self.workspaceStore = workspaceStore
    }

    public static func profileArtifactPath(runID: String) -> String {
        "\(XcircuiteWorkspace.directoryName)/runs/\(runID)/\(relativePath)"
    }

    @discardableResult
    public func persistProfile(
        _ profile: XcircuiteFlowToolchainProfile,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let runDirectory = try XcircuiteWorkspace(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let profileURL = runDirectory.appending(path: Self.relativePath)
        try workspaceStore.writeJSON(profile, to: profileURL, forProjectAt: projectRoot)

        let reference = try workspaceStore.fileReference(
            forProjectRelativePath: Self.profileArtifactPath(runID: runID),
            artifactID: Self.artifactID,
            kind: .technology,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try workspaceStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }
}
