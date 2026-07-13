import Foundation
import CircuiteFoundation
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

    /// Builds the canonical Foundation artifact reference used by new stage
    /// results. The URL is first reduced to a project-relative location so
    /// the resulting reference remains portable across workspace roots.
    func reference(
        for url: URL,
        projectRoot: URL,
        artifactID: String? = nil,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let relativePath = try pathBoundary.relativePath(for: url, projectRoot: projectRoot)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: relativePath),
            role: role,
            kind: kind,
            format: format
        )
        return try LocalArtifactReferencer().reference(
            locator,
            relativeTo: projectRoot,
            producer: nil
        ).withArtifactID(artifactID)
    }

    func optionalReference(
        for path: String,
        projectRoot: URL,
        artifactID: String? = nil,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference? {
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
            role: role,
            kind: kind,
            format: format
        )
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

private extension ArtifactReference {
    func withArtifactID(_ rawValue: String?) throws -> ArtifactReference {
        guard let rawValue else {
            return self
        }
        return ArtifactReference(
            id: try ArtifactID(rawValue: rawValue),
            locator: locator,
            digest: digest,
            byteCount: byteCount,
            producer: producer
        )
    }
}
