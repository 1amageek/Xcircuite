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
        return try await workspaceStore.persistArtifact(
            content: data,
            id: reference.id,
            locator: reference.locator,
            runID: runID,
            mode: .replaceable
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
