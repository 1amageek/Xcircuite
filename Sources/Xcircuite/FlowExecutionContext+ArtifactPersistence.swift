import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension FlowExecutionContext {
    func persistArtifactEnvelope(
        _ envelope: FlowArtifactEnvelope,
        producer: ProducerIdentity? = nil
    ) async throws -> ArtifactReference {
        try FlowArtifactEnvelopeValidator().validate(envelope)
        let integrity = await infrastructure.verifyArtifact(envelope.reference)
        guard integrity.isVerified else {
            throw FlowArtifactEnvelopeValidationError.referenceIntegrityFailed(
                path: envelope.reference.path,
                message: integrity.issues.map { $0.code.rawValue }.joined(separator: ", ")
            )
        }
        guard let stageID = envelope.stageID,
              !stageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlowArtifactEnvelopeValidationError.emptyField("stageID")
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelopeID = ArtifactID(
            stableKey: "\(stageID):\(envelope.artifactID):envelope"
        ).rawValue
        let locator = ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/evidence/\(stageID)/\(stageID)-\(envelope.artifactID)-envelope.json"
            ),
            role: .output,
            kind: .report,
            format: .json
        )
        if let producer {
            return try await infrastructure.persistArtifact(
                content: encoder.encode(envelope),
                id: try ArtifactID(rawValue: envelopeID),
                locator: locator,
                runID: runID,
                producer: producer,
                mode: .replaceable
            )
        }
        return try await infrastructure.persistArtifact(
            content: encoder.encode(envelope),
            id: try ArtifactID(rawValue: envelopeID),
            locator: locator,
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
        producer: ProducerIdentity? = nil,
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
            producer: producer,
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
        producer: ProducerIdentity? = nil,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/stages/\(stageID)/\(directory)/\(fileName)"
            ),
            role: role,
            kind: kind,
            format: format
        )
        if let producer {
            return try await infrastructure.persistArtifact(
                content: content,
                id: ArtifactID(rawValue: artifactID),
                locator: locator,
                runID: runID,
                producer: producer,
                mode: mode
            )
        }
        return try await infrastructure.persistArtifact(
            content: content,
            id: ArtifactID(rawValue: artifactID),
            locator: locator,
            runID: runID,
            mode: mode
        )
    }
}
