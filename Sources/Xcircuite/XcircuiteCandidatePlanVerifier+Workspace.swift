import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteCandidatePlanVerifier {
    func projectURL(for relativePath: String, projectRoot: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: relativePath,
                reason: "project artifact path must be relative"
            )
        }
        let url = projectRoot.appending(path: relativePath).standardizedFileURL
        guard ProjectPathBoundary().contains(url, projectRoot: projectRoot) else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: url.path(percentEncoded: false),
                projectRoot: projectRoot.path(percentEncoded: false)
            )
        }
        return url
    }

    func workspacePath(for url: URL, projectRoot: URL) throws -> String {
        let path = try ProjectPathBoundary().relativePath(for: url, projectRoot: projectRoot)
        guard path == XcircuiteWorkspaceLayout.directoryName
                || path.hasPrefix("\(XcircuiteWorkspaceLayout.directoryName)/") else {
            throw XcircuiteWorkspaceStoreError.pathOutsideWorkspace(path)
        }
        return path
    }

    func ensureWorkspaceDirectory(at url: URL, projectRoot: URL) async throws {
        try await workspaceStore.ensureWorkspaceDirectory(
            at: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func writeWorkspaceJSON<Value: Encodable & Sendable>(
        _ value: Value,
        to url: URL,
        projectRoot: URL
    ) async throws {
        try await workspaceStore.writeJSON(
            value,
            to: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func writeWorkspaceText(
        _ value: String,
        to url: URL,
        projectRoot: URL
    ) async throws {
        try await workspaceStore.writeWorkspaceText(
            value,
            to: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func retainRunArtifacts(
        _ references: [ArtifactReference],
        runID: String,
        projectRoot: URL
    ) async throws -> [ArtifactReference] {
        var retained: [ArtifactReference] = []
        for reference in references {
            let url = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
            retained.append(
                try await workspaceStore.persistArtifact(
                    content: Data(contentsOf: url, options: [.mappedIfSafe]),
                    id: reference.id,
                    locator: reference.locator,
                    runID: runID,
                    mode: .replaceable
                )
            )
        }
        return retained
    }
}
