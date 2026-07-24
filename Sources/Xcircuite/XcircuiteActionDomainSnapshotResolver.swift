import Foundation
import CircuiteFoundation
import DesignFlowKernel

struct XcircuiteResolvedActionDomainSnapshot: Sendable, Hashable {
    var snapshot: XcircuitePlanningActionDomainSnapshot
    var reference: ArtifactReference
}

enum XcircuiteActionDomainSnapshotResolutionError: Error, LocalizedError, Equatable {
    case artifactNotFound(runID: String, artifactID: String)
    case artifactIntegrityFailed(path: String, status: FlowArtifactVerificationStatus, message: String)
    case invalidArtifactReference(path: String, reason: String)
    case runMismatch(expected: String, actual: String)
    case producedByRunMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain action-domain artifact \(artifactID)."
        case .artifactIntegrityFailed(let path, let status, let message):
            "Action-domain artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .invalidArtifactReference(let path, let reason):
            "Action-domain artifact reference \(path) is invalid: \(reason)"
        case .runMismatch(let expected, let actual):
            "Action-domain snapshot run mismatch: expected \(expected), got \(actual)."
        case .producedByRunMismatch(let expected, let actual):
            "Action-domain artifact producer run mismatch: expected \(expected), got \(actual)."
        }
    }
}

struct XcircuiteActionDomainSnapshotResolver: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let verifier: LocalArtifactVerifier

    init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        verifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.verifier = verifier
    }

    func loadDefaultOrPersist(
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot {
        if let existing = manifest.artifacts.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        }) {
            let reusable = try await reusableDefaultSnapshot(
                existing,
                runID: runID,
                projectRoot: projectRoot
            )
            if let reusable {
                return reusable
            }
        }
        if let actionSnapshot = try await latestActionSnapshot(
            runID: runID,
            projectRoot: projectRoot
        ) {
            return actionSnapshot
        }
        return try await persistAndLoad(runID: runID, projectRoot: projectRoot)
    }

    func loadExplicitOrDefault(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot {
        if let explicitPath {
            return try await loadExplicitPath(
                explicitPath,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID,
                runID: runID
            )
        }

        let resolvedArtifactID = artifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID
        if let existing = manifest.artifacts.first(where: { $0.artifactID == resolvedArtifactID }) {
            return try await verifiedManifestSnapshot(
                existing,
                expectedArtifactID: resolvedArtifactID,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        if artifactID == nil {
            if let actionSnapshot = try await latestActionSnapshot(
                runID: runID,
                projectRoot: projectRoot
            ) {
                return actionSnapshot
            }
            return try await persistAndLoad(runID: runID, projectRoot: projectRoot)
        }
        throw XcircuiteActionDomainSnapshotResolutionError.artifactNotFound(
            runID: runID,
            artifactID: resolvedArtifactID
        )
    }

    private func loadExplicitPath(
        _ path: String,
        artifactID: String,
        runID: String
    ) async throws -> XcircuiteResolvedActionDomainSnapshot {
        let snapshot = try await workspaceStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: path)
        guard snapshot.runID == runID else {
            throw XcircuiteActionDomainSnapshotResolutionError.runMismatch(
                expected: runID,
                actual: snapshot.runID
            )
        }
        let reference = try await workspaceStore.makeArtifactReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: .json
        )
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }

    private func reusableDefaultSnapshot(
        _ reference: ArtifactReference,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot? {
        guard reference.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID,
              reference.kind == .other,
              reference.format == .json else {
            return nil
        }
        let integrity = verifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            return nil
        }
        do {
            _ = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            return nil
        }
        let snapshot = try await workspaceStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: reference.path)
        guard snapshot.runID == runID else {
            return nil
        }
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }

    private func latestActionSnapshot(
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot? {
        let ledger = try await workspaceStore.loadRunLedger(runID: runID)
        guard let reference = ledger.actions.reversed()
            .lazy
            .flatMap(\.outputs)
            .first(where: {
                $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
            }) else {
            return nil
        }
        return try await reusableDefaultSnapshot(
            reference,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func verifiedManifestSnapshot(
        _ reference: ArtifactReference,
        expectedArtifactID: String,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot {
        guard reference.artifactID == expectedArtifactID else {
            throw XcircuiteActionDomainSnapshotResolutionError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match the requested artifact."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuiteActionDomainSnapshotResolutionError.invalidArtifactReference(
                path: reference.path,
                reason: "action-domain snapshots must be JSON artifacts."
            )
        }
        let integrity = verifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteActionDomainSnapshotResolutionError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
        do {
            _ = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            throw XcircuiteActionDomainSnapshotResolutionError.invalidArtifactReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
        let snapshot = try await workspaceStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: reference.path)
        guard snapshot.runID == runID else {
            throw XcircuiteActionDomainSnapshotResolutionError.runMismatch(
                expected: runID,
                actual: snapshot.runID
            )
        }
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }

    private func persistAndLoad(
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedActionDomainSnapshot {
        let reference = try await artifactStore.persistActionDomainSnapshot(
            runID: runID,
            projectRoot: projectRoot
        )
        let snapshot = try await workspaceStore.readJSON(
            XcircuitePlanningActionDomainSnapshot.self,
            from: reference.path
        )
        guard snapshot.runID == runID else {
            throw XcircuiteActionDomainSnapshotResolutionError.runMismatch(
                expected: runID,
                actual: snapshot.runID
            )
        }
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }
}
