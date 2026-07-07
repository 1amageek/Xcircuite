import Foundation
import XcircuitePackage

public struct XcircuiteFlowToolchainProfileArtifactStore: Sendable {
    public static let artifactID = "flow-toolchain-profile"
    public static let relativePath = "toolchain-profile.json"

    private let packageStore: XcircuitePackageStore

    public init(packageStore: XcircuitePackageStore = XcircuitePackageStore()) {
        self.packageStore = packageStore
    }

    public static func profileArtifactPath(runID: String) -> String {
        "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
    }

    @discardableResult
    public func persistProfile(
        _ profile: XcircuiteFlowToolchainProfile,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let profileURL = runDirectory.appending(path: Self.relativePath)
        try packageStore.writeJSON(profile, to: profileURL, forProjectAt: projectRoot)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: Self.profileArtifactPath(runID: runID),
            artifactID: Self.artifactID,
            kind: .technology,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }
}
