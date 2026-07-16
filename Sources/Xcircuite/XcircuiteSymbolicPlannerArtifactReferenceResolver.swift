import Foundation
import CircuiteFoundation
import DesignFlowKernel

struct XcircuiteSymbolicPlannerArtifactReferenceResolver: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactVerifier: LocalArtifactVerifier

    init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactVerifier = artifactVerifier
    }

    func runManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    func uniqueManifestArtifact(
        artifactID: String,
        field: String,
        expectedFormat: ArtifactFormat,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        guard matches.count == 1 else {
            throw XcircuiteSymbolicPlannerSolverError.duplicateArtifactReference(
                runID: runID,
                artifactID: artifactID,
                count: matches.count
            )
        }
        let reference = matches[0]
        try validateArtifactReferenceShape(
            reference,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID
        )
        try validateArtifactIntegrity(reference, field: field, projectRoot: projectRoot)
        return reference
    }

    func projectFileReference(
        path: String,
        artifactID: String? = nil,
        field: String,
        expectedFormat: ArtifactFormat,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let reference = try await workspaceStore.makeArtifactReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: expectedFormat
        )
        try validateArtifactReferenceShape(
            reference,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID
        )
        try validateArtifactIntegrity(reference, field: field, projectRoot: projectRoot)
        return reference
    }

    func projectArtifactReference(
        path: String,
        artifactID: String? = nil,
        field: String,
        expectedFormat: ArtifactFormat,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await projectFileReference(
            path: path,
            artifactID: artifactID,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    func uniqueManifestArtifactReference(
        artifactID: String,
        field: String,
        expectedFormat: ArtifactFormat,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await uniqueManifestArtifact(
            artifactID: artifactID,
            field: field,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    func verifiedArtifactReference(
        _ reference: ArtifactReference,
        field: String,
        expectedFormat: ArtifactFormat,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try validateArtifactReferenceShape(
            reference,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID
        )
        let artifactID = reference.artifactID
        let manifest = try await runManifest(runID: runID)
        let manifestReference = try await uniqueManifestArtifact(
            artifactID: artifactID,
            field: field,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
        guard manifestReference.path == reference.path else {
            throw XcircuiteSymbolicPlannerSolverError.artifactReferenceMismatch(
                field: field,
                artifactID: artifactID,
                path: reference.path,
                manifestPath: manifestReference.path
            )
        }
        guard manifestReference.digest == reference.digest,
              manifestReference.byteCount == reference.byteCount else {
            throw XcircuiteSymbolicPlannerSolverError.artifactIntegrityFailed(
                field: field,
                artifactID: artifactID,
                path: reference.path,
                status: .sha256Mismatch,
                message: "Embedded artifact reference digest or byte count does not match the run manifest."
            )
        }
        return manifestReference
    }

    private func validateArtifactReferenceShape(
        _ reference: ArtifactReference,
        field: String,
        expectedFormat: ArtifactFormat,
        runID: String
    ) throws {
        guard reference.format == expectedFormat else {
            throw XcircuiteSymbolicPlannerSolverError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected format \(expectedFormat.rawValue), got \(reference.format.rawValue)"
            )
        }
        guard reference.kind == .other else {
            throw XcircuiteSymbolicPlannerSolverError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected file kind \(ArtifactKind.other.rawValue), got \(reference.kind.rawValue)"
            )
        }
    }

    private func validateArtifactIntegrity(
        _ reference: ArtifactReference,
        field: String,
        projectRoot: URL
    ) throws {
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteSymbolicPlannerSolverError.artifactIntegrityFailed(
                field: field,
                artifactID: reference.artifactID,
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }
}
