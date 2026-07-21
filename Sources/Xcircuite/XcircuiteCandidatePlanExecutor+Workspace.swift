import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteCandidatePlanExecutor {
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

    func retainRunArtifact(
        _ reference: ArtifactReference,
        runID: String
    ) async throws -> ArtifactReference {
        let url = try reference.locator.location.resolvedFileURL(relativeTo: workspaceStore.projectRoot)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let pathComponents = reference.path.split(separator: "/", omittingEmptySubsequences: false)
        let directory = pathComponents.dropLast().joined(separator: "/")
        let fileName = String(pathComponents.last ?? "artifact")
        let retainedPath = "\(directory)/artifacts/\(digest.hexadecimalValue)/\(fileName)"
        let retainedLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: retainedPath),
            role: reference.locator.role,
            kind: reference.locator.kind,
            format: reference.locator.format
        )
        return try await workspaceStore.persistArtifact(
            content: data,
            id: reference.id,
            locator: retainedLocator,
            runID: runID,
            mode: .immutable
        )
    }

    func retainRunArtifacts(
        _ references: [ArtifactReference],
        runID: String
    ) async throws -> [ArtifactReference] {
        var retained: [ArtifactReference] = []
        for reference in references {
            retained.append(try await retainRunArtifact(reference, runID: runID))
        }
        return retained
    }
}
