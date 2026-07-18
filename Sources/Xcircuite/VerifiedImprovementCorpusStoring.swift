import CircuiteFoundation
import DesignFlowKernel
import Foundation

/// Persistence capabilities required to assess a verified-improvement corpus.
///
/// The contract uses canonical Foundation artifacts and the DesignFlowKernel
/// ledger directly. It intentionally does not expose filesystem compatibility
/// operations or a second run-manifest representation.
public protocol VerifiedImprovementCorpusStoring: Sendable {
    var projectRoot: URL { get }

    func persistProjectJSON<Value: Encodable & Sendable>(
        _ value: Value,
        id: String,
        path: String,
        kind: ArtifactKind,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference

    func loadRunManifest(runID: String) async throws -> FlowRunManifest

    func verifiedData(for reference: ArtifactReference) async throws -> Data
}

extension XcircuiteWorkspaceStore: VerifiedImprovementCorpusStoring {}
