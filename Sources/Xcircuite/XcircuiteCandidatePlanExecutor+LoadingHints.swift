import CoreSpiceIO
import CircuiteFoundation
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanExecutor {
    func projectURL(for relativePath: String, projectRoot: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
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

    func executionDirectoryURL(
        plan: XcircuiteCandidatePlan,
        step: XcircuiteCandidatePlanStep,
        projectRoot: URL
    ) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .runDirectoryURL(for: plan.runID)
            .appending(path: "planning")
            .appending(path: "executions")
            .appending(path: plan.planID)
            .appending(path: step.stepID)
    }

    func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        try await workspaceStore.loadRunManifest(runID: runID)
    }

    func requiredCandidatePlanReference(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        if let explicitPath {
            let matches = manifest.artifacts.filter { $0.path == explicitPath }
            guard matches.count <= 1 else {
                throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                    path: explicitPath,
                    reason: "multiple manifest artifacts reference the same explicit path."
                )
            }
            let reference = try matches.first ?? artifactBuilder.reference(
                for: projectURL(for: explicitPath, projectRoot: projectRoot),
                projectRoot: projectRoot,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                kind: .other,
                format: .json
            )
            try validateCandidatePlanReference(
                reference,
                expectedArtifactID: artifactID,
                runID: runID,
                projectRoot: projectRoot
            )
            return reference
        }
        guard let artifactID else {
            throw XcircuiteCandidatePlanExecutionError.missingCandidatePlanReference
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuiteCandidatePlanExecutionError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        guard matches.count == 1 else {
            throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                path: artifactID,
                reason: "run manifest contains \(matches.count) artifacts with the same artifact ID."
            )
        }
        let reference = matches[0]
        try validateCandidatePlanReference(
            reference,
            expectedArtifactID: artifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func validateCandidatePlanReference(
        _ reference: ArtifactReference,
        expectedArtifactID: String?,
        runID: String,
        projectRoot: URL
    ) throws {
        if let expectedArtifactID, reference.artifactID != expectedArtifactID {
            throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                path: reference.path,
                reason: "candidate plans must be JSON artifacts."
            )
        }
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteCandidatePlanExecutionError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }

    func uuidHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep,
        fallbackIndex: Int
    ) throws -> UUID {
        if let raw = stringHint(key, step: step) {
            guard let uuid = UUID(uuidString: raw) else {
                throw XcircuiteCandidatePlanExecutionError.invalidHint(
                    stepID: step.stepID,
                    key: key,
                    expected: "UUID string"
                )
            }
            return uuid
        }
        return fallbackUUID(fallbackIndex)
    }

    func optionalUUIDHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) throws -> UUID? {
        guard let raw = stringHint(key, step: step) else {
            return nil
        }
        guard let uuid = UUID(uuidString: raw) else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "UUID string"
            )
        }
        return uuid
    }

    func optionalNumberHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) throws -> Double? {
        guard let value = step.parameterHints[key] else {
            return nil
        }
        guard case .scalar(let number) = value, number.isFinite else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "finite number"
            )
        }
        return number
    }

}
