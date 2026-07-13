import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func persistRejectedPlanIfNeeded(
        status: String,
        verification: XcircuitePlanVerification,
        candidatePlanRef: XcircuiteFileReference,
        verificationRef: XcircuiteFileReference,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        guard status == "rejected" || status == "blocked" else {
            return nil
        }
        let record = XcircuiteRejectedPlanRecord(
            rejectionID: rejectedPlanIdentifier(verification: verification, status: status),
            runID: verification.runID,
            problemID: verification.problemID,
            planID: verification.planID,
            verificationMode: verification.verificationMode,
            status: status,
            sourceParameterCandidateIDs: try sourceParameterCandidateIDs(
                from: verification,
                projectRoot: projectRoot
            ),
            failedStepIDs: verification.stepResults
                .filter { $0.status == "failed" || $0.status == "blocked" }
                .map(\.stepID),
            failedGateIDs: verification.gateResults
                .filter { $0.status == "failed" || $0.status == "blocked" }
                .map(\.gateID),
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: verificationRef,
            artifactRefs: verification.artifactRefs,
            diagnostics: verification.diagnostics,
            diagnosticClassifications: XcircuiteRejectedPlanDiagnosticClassifier().classify(
                verification: verification,
                status: status
            ),
            nextActions: verification.nextActions
        )
        return try artifactStore.appendRejectedPlan(
            record,
            runID: verification.runID,
            projectRoot: projectRoot
        )
    }

    func rejectedPlanIdentifier(
        verification: XcircuitePlanVerification,
        status: String
    ) -> String {
        "\(verification.runID)-\(verification.planID)-\(verification.verificationMode)-\(status)"
    }

    func sourceParameterCandidateIDs(
        from verification: XcircuitePlanVerification,
        projectRoot: URL
    ) throws -> [String] {
        var ids: [String] = []
        for reference in verification.artifactRefs {
            guard reference.artifactID?.hasSuffix("-netlist-parameter-edit-report") == true else {
                continue
            }
            let report = try packageStore.readJSON(
                XcircuiteNetlistParameterEditReport.self,
                from: packageStore.url(forProjectRelativePath: reference.path, inProjectAt: projectRoot)
            )
            if let sourceParameterCandidateID = report.sourceParameterCandidateID {
                ids.append(sourceParameterCandidateID)
            }
        }
        return unique(ids.filter { !$0.isEmpty })
    }

    func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    func appendActionRecord(
        verification: XcircuitePlanVerification,
        candidatePlanRef: XcircuiteFileReference,
        verificationRef: XcircuiteFileReference,
        rejectedPlansRef: XcircuiteFileReference?,
        projectRoot: URL
    ) throws {
        let actionStatus: XcircuiteRunActionStatus
        switch verificationStatus(for: verification) {
        case "accepted":
            actionStatus = .succeeded
        case "blocked":
            actionStatus = .blocked
        case "rejected":
            actionStatus = .failed
        default:
            actionStatus = .partial
        }
        let diagnostics = verification.diagnostics.map {
            XcircuiteRunActionDiagnostic(
                severity: runActionSeverity($0.severity),
                code: $0.code,
                message: $0.message
            )
        }
        try packageStore.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "\(verification.planID)-verification",
                runID: verification.runID,
                actor: XcircuiteRunActionActor(kind: .cli, identifier: "xcircuite-flow"),
                actionKind: "planning.verify-candidate-plan",
                status: actionStatus,
                inputs: [candidatePlanRef],
                outputs: [verificationRef] + [rejectedPlansRef].compactMap { $0 },
                diagnostics: diagnostics
            ),
            inProjectAt: projectRoot
        )
    }

    func runActionSeverity(_ severity: String) -> XcircuiteRunActionDiagnosticSeverity {
        switch severity {
        case "info":
            return .info
        case "warning":
            return .warning
        default:
            return .error
        }
    }

    func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    func loadPlanningProblem(
        for plan: XcircuiteCandidatePlan,
        projectRoot: URL
    ) throws -> XcircuiteCircuitPlanningProblem? {
        guard let path = plan.sourceProblemRef.path else {
            return nil
        }
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let problem = try packageStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: url
        )
        guard problem.runID == plan.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: plan.runID,
                actual: problem.runID
            )
        }
        return problem
    }

    func loadOrPersistActionDomainSnapshot(
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ActionDomainSnapshotContext {
        let resolved = try XcircuiteActionDomainSnapshotResolver(
            packageStore: packageStore,
            artifactStore: artifactStore
        ).loadDefaultOrPersist(
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
        return ActionDomainSnapshotContext(snapshot: resolved.snapshot, reference: resolved.reference)
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
                throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
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
            throw XcircuiteCandidatePlanVerificationError.missingCandidatePlanReference
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuiteCandidatePlanVerificationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        guard matches.count == 1 else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
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
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "candidate plans must be JSON artifacts."
            )
        }
        guard reference.producedByRunID == runID else {
            throw XcircuiteCandidatePlanVerificationError.artifactProducerRunMismatch(
                expected: runID,
                actual: reference.producedByRunID
            )
        }
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteCandidatePlanVerificationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
    }
}
