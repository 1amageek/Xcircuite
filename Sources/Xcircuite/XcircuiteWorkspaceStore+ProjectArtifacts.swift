import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    public func persistProjectJSON<Value: Encodable & Sendable>(
        _ value: Value,
        id: String,
        path: String,
        kind: ArtifactKind = .report,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistProjectArtifact(
            content: encoder.encode(value),
            id: ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: .json
            ),
            mode: mode
        )
    }

    public func persistProjectText(
        _ value: String,
        id: String,
        path: String,
        kind: ArtifactKind = .report,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        try await persistProjectArtifact(
            content: Data(value.utf8),
            id: ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: .text
            ),
            mode: mode
        )
    }
}
