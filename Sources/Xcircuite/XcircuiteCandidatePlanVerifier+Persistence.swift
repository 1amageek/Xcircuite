import Foundation
import CircuiteFoundation
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
        candidatePlanRef: ArtifactReference,
        verificationRef: ArtifactReference,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
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
        return try await artifactStore.appendRejectedPlan(
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
        let artifactReferences = verification.artifactRefs
        var ids: [String] = []
        for reference in artifactReferences {
            guard reference.id.rawValue.hasSuffix("-netlist-parameter-edit-report") else {
                continue
            }
            let storageReference = reference
            let report = try JSONDecoder().decode(
                XcircuiteNetlistParameterEditReport.self,
                from: Data(contentsOf: projectURL(for: storageReference.path, projectRoot: projectRoot))
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
        candidatePlanRef: ArtifactReference,
        verificationRef: ArtifactReference,
        rejectedPlansRef: ArtifactReference?,
        projectRoot: URL
    ) async throws {
        let actionStatus: FlowRunActionStatus
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
            FlowRunDiagnostic(
                severity: runActionSeverity($0.severity),
                code: $0.code,
                message: $0.message
            )
        }
        try await workspaceStore.appendRunAction(
            FlowRunActionRecord(
                actionID: "\(verification.planID)-verification",
                runID: verification.runID,
                actor: FlowRunActor(kind: .cli, identifier: "xcircuite-flow"),
                actionKind: "planning.verify-candidate-plan",
                status: actionStatus,
                inputs: [candidatePlanRef],
                outputs: [verificationRef] + [rejectedPlansRef].compactMap { $0 },
                diagnostics: diagnostics
            )
        )
    }

    func runActionSeverity(_ severity: String) -> FlowRunDiagnosticSeverity {
        switch severity {
        case "info":
            return .info
        case "warning":
            return .warning
        default:
            return .error
        }
    }

    func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        try await workspaceStore.loadRunManifest(runID: runID)
    }

    func loadPlanningProblem(
        for plan: XcircuiteCandidatePlan,
        projectRoot: URL
    ) throws -> XcircuiteCircuitPlanningProblem? {
        guard let path = plan.sourceProblemRef.path else {
            return nil
        }
        let url = try projectURL(for: path, projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let problem = try JSONDecoder().decode(
            XcircuiteCircuitPlanningProblem.self,
            from: Data(contentsOf: url)
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
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ActionDomainSnapshotContext {
        let resolved = try await XcircuiteActionDomainSnapshotResolver(
            workspaceStore: workspaceStore,
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
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        if let explicitPath {
            let matches = manifest.artifacts.filter { $0.path == explicitPath }
            guard matches.count <= 1 else {
                throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
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
        _ reference: ArtifactReference,
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
        let integrity = makeArtifactReferenceVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteCandidatePlanVerificationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }
}
