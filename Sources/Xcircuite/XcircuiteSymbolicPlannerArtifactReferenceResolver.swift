import Foundation
import CircuiteFoundation
import DesignFlowKernel

struct XcircuiteSymbolicPlannerArtifactReferenceResolver: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    func runManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try workspaceStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    func uniqueManifestArtifact(
        artifactID: String,
        field: String,
        expectedFormat: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
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
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let reference = try workspaceStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: expectedFormat,
            inProjectAt: projectRoot,
            producedByRunID: runID
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
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        try requireFoundationArtifactReference(
            projectFileReference(
                path: path,
                artifactID: artifactID,
                field: field,
                expectedFormat: expectedFormat,
                runID: runID,
                projectRoot: projectRoot
            ),
            field: field
        )
    }

    func uniqueManifestArtifactReference(
        artifactID: String,
        field: String,
        expectedFormat: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        try requireFoundationArtifactReference(
            uniqueManifestArtifact(
                artifactID: artifactID,
                field: field,
                expectedFormat: expectedFormat,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot
            ),
            field: field
        )
    }

    func verifiedArtifactReference(
        _ reference: XcircuiteFileReference,
        field: String,
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try validateArtifactReferenceShape(
            reference,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID
        )
        guard let artifactID = reference.artifactID else {
            try validateArtifactIntegrity(reference, field: field, projectRoot: projectRoot)
            return reference
        }

        let manifest = try runManifest(runID: runID, projectRoot: projectRoot)
        let manifestReference = try uniqueManifestArtifact(
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
        guard manifestReference.sha256 == reference.sha256,
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
        _ reference: XcircuiteFileReference,
        field: String,
        expectedFormat: XcircuiteFileFormat,
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
                reason: "expected file kind \(XcircuiteFileKind.other.rawValue), got \(reference.kind.rawValue)"
            )
        }
        guard let producedByRunID = reference.producedByRunID else {
            throw XcircuiteSymbolicPlannerSolverError.artifactProducerRunMismatch(
                field: field,
                expected: runID,
                actual: nil
            )
        }
        guard producedByRunID == runID else {
            throw XcircuiteSymbolicPlannerSolverError.artifactProducerRunMismatch(
                field: field,
                expected: runID,
                actual: producedByRunID
            )
        }
    }

    private func validateArtifactIntegrity(
        _ reference: XcircuiteFileReference,
        field: String,
        projectRoot: URL
    ) throws {
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteSymbolicPlannerSolverError.artifactIntegrityFailed(
                field: field,
                artifactID: reference.artifactID,
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
    }
}
