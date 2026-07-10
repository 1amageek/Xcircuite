import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import XcircuitePackage

extension XcircuiteCandidatePlanExecutor {
    func executionDirectoryURL(
        plan: XcircuiteCandidatePlan,
        step: XcircuiteCandidatePlanStep,
        projectRoot: URL
    ) throws -> URL {
        try XcircuitePackage(projectRoot: projectRoot)
            .runDirectoryURL(for: plan.runID)
            .appending(path: "planning")
            .appending(path: "executions")
            .appending(path: plan.planID)
            .appending(path: step.stepID)
    }

    func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    func requiredCandidatePlanReference(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        if let explicitPath {
            let matches = manifest.artifacts.filter { $0.path == explicitPath }
            guard matches.count <= 1 else {
                throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                    path: explicitPath,
                    reason: "multiple manifest artifacts reference the same explicit path."
                )
            }
            let reference = try matches.first ?? packageStore.fileReference(
                forProjectRelativePath: explicitPath,
                artifactID: artifactID,
                kind: .other,
                format: .json,
                inProjectAt: projectRoot,
                producedByRunID: runID
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
        _ reference: XcircuiteFileReference,
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
        guard reference.producedByRunID == runID else {
            throw XcircuiteCandidatePlanExecutionError.artifactProducerRunMismatch(
                expected: runID,
                actual: reference.producedByRunID
            )
        }
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteCandidatePlanExecutionError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
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
        guard case .number(let number) = value, number.isFinite else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "finite number"
            )
        }
        return number
    }

    func decodedHint<T: Decodable>(
        _ key: String,
        from step: XcircuiteCandidatePlanStep
    ) throws -> T? {
        guard let value = step.parameterHints[key] else {
            return nil
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
