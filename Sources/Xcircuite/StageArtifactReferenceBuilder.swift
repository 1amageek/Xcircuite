import Foundation
import DesignFlowKernel

struct StageArtifactReferenceBuilder: Sendable {
    private let hasher: XcircuiteHasher
    private let pathBoundary: ProjectPathBoundary

    init(
        hasher: XcircuiteHasher = XcircuiteHasher(),
        pathBoundary: ProjectPathBoundary = ProjectPathBoundary()
    ) {
        self.hasher = hasher
        self.pathBoundary = pathBoundary
    }

    func reference(
        for url: URL,
        projectRoot: URL,
        artifactID: String? = nil,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        producedByRunID: String
    ) throws -> XcircuiteFileReference {
        if let artifactID {
            try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
        }
        let relativePath = try pathBoundary.relativePath(for: url, projectRoot: projectRoot)
        let digest = try hasher.sha256(fileAt: url)
        let byteCount = try hasher.byteCount(fileAt: url)
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: relativePath,
            kind: kind,
            format: format,
            sha256: digest,
            byteCount: byteCount,
            producedByRunID: producedByRunID
        )
    }

    func optionalReference(
        for path: String,
        projectRoot: URL,
        artifactID: String? = nil,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        producedByRunID: String
    ) throws -> XcircuiteFileReference? {
        guard !path.isEmpty else {
            return nil
        }
        let url = URL(filePath: path)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try reference(
            for: url,
            projectRoot: projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format,
            producedByRunID: producedByRunID
        )
    }
}
