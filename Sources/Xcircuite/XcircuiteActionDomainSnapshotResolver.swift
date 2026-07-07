import Foundation
import XcircuitePackage

struct XcircuiteResolvedActionDomainSnapshot: Sendable, Hashable {
    var snapshot: XcircuitePlanningActionDomainSnapshot
    var reference: XcircuiteFileReference
}

enum XcircuiteActionDomainSnapshotResolutionError: Error, LocalizedError, Equatable {
    case artifactNotFound(runID: String, artifactID: String)
    case artifactIntegrityFailed(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
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
    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let verifier: XcircuiteFileReferenceVerifier

    init(
        packageStore: XcircuitePackageStore,
        artifactStore: XcircuitePlanningArtifactStore,
        verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.verifier = verifier
    }

    func loadDefaultOrPersist(
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteResolvedActionDomainSnapshot {
        if let existing = manifest.artifacts.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        }) {
            let reusable = try reusableDefaultSnapshot(
                existing,
                runID: runID,
                projectRoot: projectRoot
            )
            if let reusable {
                return reusable
            }
        }
        return try persistAndLoad(runID: runID, projectRoot: projectRoot)
    }

    func loadExplicitOrDefault(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteResolvedActionDomainSnapshot {
        if let explicitPath {
            return try loadExplicitPath(
                explicitPath,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID,
                runID: runID,
                projectRoot: projectRoot
            )
        }

        let resolvedArtifactID = artifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID
        if let existing = manifest.artifacts.first(where: { $0.artifactID == resolvedArtifactID }) {
            return try verifiedManifestSnapshot(
                existing,
                expectedArtifactID: resolvedArtifactID,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        if artifactID == nil {
            return try persistAndLoad(runID: runID, projectRoot: projectRoot)
        }
        throw XcircuiteActionDomainSnapshotResolutionError.artifactNotFound(
            runID: runID,
            artifactID: resolvedArtifactID
        )
    }

    private func loadExplicitPath(
        _ path: String,
        artifactID: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteResolvedActionDomainSnapshot {
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let snapshot = try packageStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: url)
        guard snapshot.runID == runID else {
            throw XcircuiteActionDomainSnapshotResolutionError.runMismatch(
                expected: runID,
                actual: snapshot.runID
            )
        }
        let reference = try packageStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }

    private func reusableDefaultSnapshot(
        _ reference: XcircuiteFileReference,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteResolvedActionDomainSnapshot? {
        guard reference.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID,
              reference.kind == .other,
              reference.format == .json else {
            return nil
        }
        if let producedByRunID = reference.producedByRunID, producedByRunID != runID {
            return nil
        }
        let integrity = verifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            return nil
        }
        guard let url = verifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            return nil
        }
        let snapshot = try packageStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: url)
        guard snapshot.runID == runID else {
            return nil
        }
        return XcircuiteResolvedActionDomainSnapshot(snapshot: snapshot, reference: reference)
    }

    private func verifiedManifestSnapshot(
        _ reference: XcircuiteFileReference,
        expectedArtifactID: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteResolvedActionDomainSnapshot {
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
        if let producedByRunID = reference.producedByRunID, producedByRunID != runID {
            throw XcircuiteActionDomainSnapshotResolutionError.producedByRunMismatch(
                expected: runID,
                actual: producedByRunID
            )
        }

        let integrity = verifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteActionDomainSnapshotResolutionError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
        guard let url = verifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            throw XcircuiteActionDomainSnapshotResolutionError.invalidArtifactReference(
                path: reference.path,
                reason: "artifact path cannot be resolved inside the project root."
            )
        }
        let snapshot = try packageStore.readJSON(XcircuitePlanningActionDomainSnapshot.self, from: url)
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
    ) throws -> XcircuiteResolvedActionDomainSnapshot {
        let reference = try artifactStore.persistActionDomainSnapshot(
            runID: runID,
            projectRoot: projectRoot
        )
        let snapshot = try packageStore.readJSON(
            XcircuitePlanningActionDomainSnapshot.self,
            from: packageStore.url(forProjectRelativePath: reference.path, inProjectAt: projectRoot)
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
