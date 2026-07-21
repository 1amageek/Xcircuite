import CircuiteFoundation
import DesignFlowKernel
import Foundation

package struct RunActionArtifactStore: FlowArtifactPersisting {
    let store: XcircuiteWorkspaceStore
    let actionKind: String

    package init(store: XcircuiteWorkspaceStore, actionKind: String) {
        self.store = store
        self.actionKind = actionKind
    }

    package func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        try await persistArtifact(
            content: content,
            id: id,
            locator: locator,
            runID: runID,
            producer: nil,
            mode: mode
        )
    }

    package func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        producer: ProducerIdentity,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        try await persistArtifact(
            content: content,
            id: id,
            locator: locator,
            runID: runID,
            producer: Optional(producer),
            mode: mode
        )
    }

    private func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        producer: ProducerIdentity?,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        _ = mode
        guard let id else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: locator.location.value
            )
        }
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let persistedLocator = try contentAddressedLocator(
            projectRelativeLocator(locator, runID: runID),
            digest: digest
        )
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: digest,
            byteCount: UInt64(content.count),
            producer: producer
        )
        let ledger = try await store.loadRunLedger(runID: runID)
        let actionID = "\(actionKind)-\(id.rawValue)-\(digest.hexadecimalValue)"
        let action: FlowRunActionRecord
        if let existing = ledger.actions.first(where: { $0.actionID == actionID }) {
            action = existing
        } else {
            let inputs = uniqueReferences(
                ledger.artifacts + ledger.actions.flatMap(\.outputs)
            ).filter { $0 != reference }
            action = FlowRunActionRecord(
                actionID: actionID,
                runID: runID,
                actor: FlowRunActor(kind: .cli, identifier: "xcircuite-flow"),
                actionKind: actionKind,
                status: .succeeded,
                inputs: inputs,
                outputs: [reference]
            )
        }
        _ = try await store.appendActionArtifact(
            content: content,
            reference: reference,
            action: action
        )
        return reference
    }

    package func loadArtifactContent(for reference: ArtifactReference) async throws -> Data {
        try await store.loadArtifactContent(for: reference)
    }

    package func loadArtifactContent(at locator: ArtifactLocator) async throws -> Data? {
        try await store.loadArtifactContent(at: locator)
    }

    package func artifactExists(at locator: ArtifactLocator) async throws -> Bool {
        try await store.artifactExists(at: locator)
    }

    package func verifyArtifact(_ reference: ArtifactReference) async -> ArtifactIntegrity {
        await store.verifyArtifact(reference)
    }

    private func projectRelativeLocator(
        _ locator: ArtifactLocator,
        runID: String
    ) throws -> ArtifactLocator {
        guard locator.location.storage == .workspaceRelative else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: locator.location.value
            )
        }
        let path = locator.location.value.hasPrefix(".xcircuite/")
            ? locator.location.value
            : ".xcircuite/\(locator.location.value)"
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: locator.role,
            kind: locator.kind,
            format: locator.format
        )
    }

    private func contentAddressedLocator(
        _ locator: ArtifactLocator,
        digest: ContentDigest
    ) throws -> ArtifactLocator {
        let path = locator.location.value
        let pathExtension = (path as NSString).pathExtension
        let basePath = pathExtension.isEmpty
            ? path
            : String(path.dropLast(pathExtension.count + 1))
        let suffix = "-sha256-\(digest.hexadecimalValue)"
        let contentAddressedPath = basePath.hasSuffix(suffix)
            ? path
            : "\(basePath)\(suffix)\(pathExtension.isEmpty ? "" : ".\(pathExtension)")"
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: contentAddressedPath),
            role: locator.role,
            kind: locator.kind,
            format: locator.format
        )
    }

    private func uniqueReferences(_ references: [ArtifactReference]) -> [ArtifactReference] {
        var seen: Set<ArtifactReference> = []
        return references
            .sorted(by: { (left: ArtifactReference, right: ArtifactReference) -> Bool in
                if left.path != right.path {
                    return left.path < right.path
                }
                if left.locator.role.rawValue != right.locator.role.rawValue {
                    return left.locator.role.rawValue < right.locator.role.rawValue
                }
                return left.artifactID < right.artifactID
            })
            .filter { seen.insert($0).inserted }
    }
}

extension RunActionArtifactStore: FlowRunEvidencePersisting {
    package func loadArtifactEnvelopeRecords(
        runID: String
    ) async throws -> [FlowArtifactEnvelopeRecord] {
        try await store.loadArtifactEnvelopeRecords(runID: runID)
    }

    package func persistCrossArtifactEvaluation(
        _ evaluation: FlowCrossArtifactEvaluation
    ) async throws -> ArtifactReference {
        try await persistJSON(
            evaluation,
            id: "cross-artifact-evaluation",
            path: ".xcircuite/runs/\(evaluation.runID)/reports/cross-artifact-evaluation.json",
            runID: evaluation.runID
        )
    }

    package func persistLoopIterationSummaries(
        _ iterations: [FlowLoopIterationSummary],
        runID: String
    ) async throws -> ArtifactReference {
        try await persistJSON(
            iterations,
            id: "agent-loop-iterations",
            path: ".xcircuite/runs/\(runID)/loop/iterations.json",
            runID: runID
        )
    }

    package func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot
    ) async throws -> ArtifactReference {
        try await persistJSON(
            snapshot,
            id: "agent-loop-snapshot",
            path: ".xcircuite/runs/\(snapshot.runID)/loop/snapshot.json",
            runID: snapshot.runID
        )
    }

    private func persistJSON<Value: Encodable>(
        _ value: Value,
        id: String,
        path: String,
        runID: String
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistArtifact(
            content: encoder.encode(value),
            id: ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: runID,
            mode: .immutable
        )
    }
}
