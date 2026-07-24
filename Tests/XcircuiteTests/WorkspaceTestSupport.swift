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
func persistTestStageResult(
    _ result: FlowStageResult,
    runID: String,
    store: XcircuiteWorkspaceStore
) async throws -> ArtifactReference {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let content = try encoder.encode(result)
    return try await store.persistRunControlArtifact(
        content: content,
        id: try ArtifactID(rawValue: "\(result.stageID)-result"),
        locator: ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/stages/\(result.stageID)/result.json"
            ),
            role: .output,
            kind: .other,
            format: .json
        ),
        runID: runID,
        mode: .replaceable
    )
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
func retainTestProjectInput(
    path: String,
    artifactID: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    runID: String,
    store: XcircuiteWorkspaceStore,
    projectRoot: URL
) async throws -> ArtifactReference {
    let reference = try await store.makeArtifactReference(
        forProjectRelativePath: path,
        artifactID: artifactID,
        role: .input,
        kind: kind,
        format: format
    )
    return try await retainTestArtifact(
        reference,
        runID: runID,
        store: store,
        projectRoot: projectRoot
    )
}

func retainLVSInputs(
    layoutPath: String,
    schematicPath: String,
    runID: String,
    store: XcircuiteWorkspaceStore,
    root: URL
) async throws {
    _ = try await retainTestProjectInput(
        path: layoutPath,
        artifactID: "\(runID)-layout-netlist-input",
        kind: .netlist,
        format: .spice,
        runID: runID,
        store: store,
        projectRoot: root
    )
    _ = try await retainTestProjectInput(
        path: schematicPath,
        artifactID: "\(runID)-schematic-netlist-input",
        kind: .netlist,
        format: .spice,
        runID: runID,
        store: store,
        projectRoot: root
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
