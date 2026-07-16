import CircuiteFoundation
import DesignFlowKernel
import Foundation
@testable import Xcircuite

@discardableResult
func prepareTestRun(
    runID: String,
    store: XcircuiteWorkspaceStore
) async throws -> URL {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let manifest = try FlowRunManifest(
        runID: runID,
        status: .created,
        actor: FlowRunActor(kind: .system, identifier: "test"),
        createdAt: timestamp,
        updatedAt: timestamp
    )
    let ledger = FlowRunLedger(
        runID: runID,
        runManifest: manifest,
        stages: []
    )
    try await store.saveRunLedger(ledger)
    return try await store.runWorkspaceURL(runID: runID)
}

@discardableResult
func retainTestArtifact(
    _ reference: ArtifactReference,
    runID: String,
    store: XcircuiteWorkspaceStore,
    projectRoot: URL
) async throws -> ArtifactReference {
    let sourceURL = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
    return try await store.persistArtifact(
        content: Data(contentsOf: sourceURL, options: [.mappedIfSafe]),
        id: reference.id,
        locator: reference.locator,
        runID: runID,
        mode: .replaceable
    )
}

@discardableResult
func persistTestArtifactEnvelope(
    _ envelope: FlowArtifactEnvelope,
    runID: String,
    store: XcircuiteWorkspaceStore
) async throws -> ArtifactReference {
    try FlowArtifactEnvelopeValidator().validate(envelope)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try await store.persistArtifact(
        content: encoder.encode(envelope),
        id: ArtifactID(stableKey: envelope.artifactID),
        locator: ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/evidence/\(envelope.artifactID)-envelope.json"
            ),
            role: .output,
            kind: .report,
            format: .json
        ),
        runID: runID,
        mode: .replaceable
    )
}
