import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension FlowExecutionContext {
    func persistArtifactEnvelope(
        _ envelope: FlowArtifactEnvelope
    ) async throws -> ArtifactReference {
        try FlowArtifactEnvelopeValidator().validate(envelope)
        let integrity = await infrastructure.verifyArtifact(envelope.reference)
        guard integrity.isVerified else {
            throw FlowArtifactEnvelopeValidationError.referenceIntegrityFailed(
                path: envelope.reference.path,
                message: integrity.issues.map { $0.code.rawValue }.joined(separator: ", ")
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelopeID = ArtifactID(stableKey: envelope.artifactID).rawValue
        return try await infrastructure.persistArtifact(
            content: encoder.encode(envelope),
            id: try ArtifactID(rawValue: envelopeID),
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

    func persistJSONArtifact<Value: Encodable>(
        _ value: Value,
        artifactID: String,
        stageID: String,
        directory: String = "raw",
        fileName: String,
        role: ArtifactRole = .output,
        kind: ArtifactKind = .report,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistArtifact(
            encoder.encode(value),
            artifactID: artifactID,
            stageID: stageID,
            directory: directory,
            fileName: fileName,
            role: role,
            kind: kind,
            format: .json,
            mode: mode
        )
    }

    func persistArtifact(
        _ content: Data,
        artifactID: String,
        stageID: String,
        directory: String = "raw",
        fileName: String,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        try await infrastructure.persistArtifact(
            content: content,
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(runID)/stages/\(stageID)/\(directory)/\(fileName)"
                ),
                role: role,
                kind: kind,
                format: format
            ),
            runID: runID,
            mode: mode
        )
    }
}
