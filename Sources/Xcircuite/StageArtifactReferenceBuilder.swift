import Foundation
import XcircuitePackage

struct StageArtifactReferenceBuilder: Sendable {
    private let hasher: XcircuiteHasher

    init(hasher: XcircuiteHasher = XcircuiteHasher()) {
        self.hasher = hasher
    }

    func reference(
        for url: URL,
        projectRoot: URL,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        producedByRunID: String
    ) throws -> XcircuiteFileReference {
        let digest = try hasher.sha256(fileAt: url)
        return XcircuiteFileReference(
            path: try projectRelativePath(for: url, projectRoot: projectRoot),
            kind: kind,
            format: format,
            sha256: digest,
            producedByRunID: producedByRunID
        )
    }

    func optionalReference(
        for path: String,
        projectRoot: URL,
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
            kind: kind,
            format: format,
            producedByRunID: producedByRunID
        )
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: filePath,
                projectRoot: rootPath
            )
        }
        return String(filePath.dropFirst(prefix.count))
    }
}
