import CircuiteFoundation
import Foundation
import ReleaseCore

extension XcircuiteWorkspaceStore: ReleaseArtifactPersisting {
    public func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo requestedProjectRoot: URL
    ) async throws -> ArtifactReference {
        guard requestedProjectRoot.standardizedFileURL == projectRoot else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(
                request.locator.location.value
            )
        }
        let digest = try SHA256ContentDigester().digest(
            data: request.bytes,
            using: .sha256
        )
        let reference = ArtifactReference(
            locator: request.locator,
            digest: digest,
            byteCount: UInt64(request.bytes.count),
            producer: request.producer
        )
        return try await persistProjectArtifact(
            content: request.bytes,
            id: reference.id,
            locator: request.locator,
            producer: request.producer,
            mode: .createOnly
        )
    }

    public func load(
        _ artifact: ArtifactReference,
        relativeTo requestedProjectRoot: URL
    ) async throws -> Data {
        guard requestedProjectRoot.standardizedFileURL == projectRoot else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(
                artifact.locator.location.value
            )
        }
        return try await loadArtifactContent(for: artifact)
    }
}
