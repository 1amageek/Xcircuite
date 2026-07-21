import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteCandidatePlanVerifier {
    func projectURL(for relativePath: String, projectRoot: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: relativePath,
                reason: "project artifact path must be relative"
            )
        }
        let url = projectRoot.appending(path: relativePath).standardizedFileURL
        guard ProjectPathBoundary().contains(url, projectRoot: projectRoot) else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: url.path(percentEncoded: false),
                projectRoot: projectRoot.path(percentEncoded: false)
            )
        }
        return url
    }

    func workspacePath(for url: URL, projectRoot: URL) throws -> String {
        let path = try ProjectPathBoundary().relativePath(for: url, projectRoot: projectRoot)
        guard path == XcircuiteWorkspaceLayout.directoryName
                || path.hasPrefix("\(XcircuiteWorkspaceLayout.directoryName)/") else {
            throw XcircuiteWorkspaceStoreError.pathOutsideWorkspace(path)
        }
        return path
    }

    func ensureWorkspaceDirectory(at url: URL, projectRoot: URL) async throws {
        try await workspaceStore.ensureWorkspaceDirectory(
            at: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func writeWorkspaceJSON<Value: Encodable & Sendable>(
        _ value: Value,
        to url: URL,
        projectRoot: URL
    ) async throws {
        try await workspaceStore.writeJSON(
            value,
            to: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func writeWorkspaceText(
        _ value: String,
        to url: URL,
        projectRoot: URL
    ) async throws {
        try await workspaceStore.writeWorkspaceText(
            value,
            to: workspacePath(for: url, projectRoot: projectRoot)
        )
    }

    func retainRunArtifacts(
        _ references: [ArtifactReference],
        runID: String,
        projectRoot: URL
    ) async throws -> [ArtifactReference] {
        var retained: [ArtifactReference] = []
        for reference in references {
            let url = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
            retained.append(
                try await workspaceStore.persistArtifact(
                    content: Data(contentsOf: url, options: [.mappedIfSafe]),
                    id: reference.id,
                    locator: reference.locator,
                    runID: runID,
                    mode: .replaceable
                )
            )
        }
        return retained
    }

    func attestedArtifactReferences(runID: String) async throws -> Set<ArtifactReference> {
        let ledger = try await workspaceStore.loadRunLedger(runID: runID)
        return Set(ledger.artifacts + ledger.actions.flatMap(\.outputs))
    }

    func attestedArtifactContent(
        for reference: ArtifactReference,
        runID: String
    ) async throws -> Data {
        let references = try await attestedArtifactReferences(runID: runID)
        guard references.contains(reference) else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "gate input artifact is not attested by the run ledger."
            )
        }
        return try await workspaceStore.loadArtifactContent(for: reference)
    }

    func retainedArtifactReference(
        for planningReference: XcircuitePlanningReference,
        runID: String
    ) async throws -> ArtifactReference {
        guard planningReference.path != nil || planningReference.artifactID != nil else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: planningReference.refID,
                reason: "gate input reference has neither path nor artifact ID."
            )
        }
        let references = try await attestedArtifactReferences(runID: runID)
        let matches = references.filter { reference in
            let pathMatches = planningReference.path.map { reference.path == $0 } ?? true
            let identifierMatches = planningReference.artifactID.map {
                reference.artifactID == $0
            } ?? true
            return pathMatches && identifierMatches
        }
        guard matches.count == 1, let reference = matches.first else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: planningReference.path ?? planningReference.artifactID ?? planningReference.refID,
                reason: "gate input must resolve to exactly one attested artifact; found \(matches.count)."
            )
        }
        return reference
    }

    func verifiedArtifactContent(
        for planningReference: XcircuitePlanningReference,
        runID: String
    ) async throws -> (reference: ArtifactReference, content: Data) {
        let reference = try await retainedArtifactReference(
            for: planningReference,
            runID: runID
        )
        return (
            reference,
            try await workspaceStore.loadArtifactContent(for: reference)
        )
    }

    func verifiedInputURL(
        for planningReference: XcircuitePlanningReference,
        runID: String
    ) async throws -> URL {
        let verified = try await verifiedArtifactContent(
            for: planningReference,
            runID: runID
        )
        let fileName = URL(fileURLWithPath: verified.reference.path).lastPathComponent
        let snapshotPath = ".xcircuite/runs/\(runID)/planning/verification/inputs/"
            + "\(verified.reference.digest.hexadecimalValue)/\(fileName)"
        try await workspaceStore.writeImmutable(verified.content, to: snapshotPath)
        return try await workspaceStore.url(for: snapshotPath)
    }

    func verifiedOptionalInputURL(
        for planningReference: XcircuitePlanningReference?,
        runID: String
    ) async throws -> URL? {
        guard let planningReference else {
            return nil
        }
        return try await verifiedInputURL(for: planningReference, runID: runID)
    }
}
