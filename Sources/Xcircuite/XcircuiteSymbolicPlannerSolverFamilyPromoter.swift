import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyPromoter: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactReferenceResolver: XcircuiteSymbolicPlannerArtifactReferenceResolver

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactReferenceResolver = XcircuiteSymbolicPlannerArtifactReferenceResolver(
            workspaceStore: workspaceStore,
            artifactVerifier: artifactVerifier
        )
    }

    public func promote(
        request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverFamilyPromotionResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        try FlowIdentifierValidator().validate(request.comparisonID, kind: .artifactID)
        let comparisonInput = try await loadComparison(request: request, projectRoot: projectRoot)
        let comparison = comparisonInput.comparison
        guard comparison.runID == request.runID else {
            throw XcircuiteSymbolicPlannerSolverError.qualificationRunMismatch(
                expected: request.runID,
                actual: comparison.runID
            )
        }
        guard comparison.comparisonID == request.comparisonID else {
            throw XcircuiteSymbolicPlannerSolverError.solverFamilyComparisonIDMismatch(
                expected: request.comparisonID,
                actual: comparison.comparisonID
            )
        }
        let selectedIndex = request.selectedCandidateIndex ?? comparison.selectedCandidateIndex
        guard comparison.candidates.indices.contains(selectedIndex) else {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateIndex(
                index: selectedIndex,
                candidateCount: comparison.candidates.count
            )
        }
        let selectedCandidate = comparison.candidates[selectedIndex]
        guard let qualificationArtifact = selectedCandidate.qualificationArtifact else {
            throw XcircuiteSymbolicPlannerSolverError.missingSelectedSolverFamilyQualificationArtifact
        }
        let qualification = try await loadQualification(
            artifact: qualificationArtifact,
            runID: request.runID,
            projectRoot: projectRoot
        )
        guard qualification.runID == request.runID else {
            throw XcircuiteSymbolicPlannerSolverError.qualificationRunMismatch(
                expected: request.runID,
                actual: qualification.runID
            )
        }
        if request.requireQualified, qualification.status != "qualified" {
            throw XcircuiteSymbolicPlannerSolverError.selectedSolverFamilyQualificationNotQualified(
                toolID: qualification.toolID,
                status: qualification.status
            )
        }
        guard let importResult = qualification.solverResult.importResult else {
            throw XcircuiteSymbolicPlannerSolverError.missingSelectedSolverFamilyImportedPlan(
                toolID: qualification.toolID
            )
        }

        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        let promotedSolverPlanArtifact = try await promoteSolverPlanIfAvailable(
            qualification: qualification,
            runID: request.runID,
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        )
        let promotedCandidatePlanArtifact = try await artifactStore.persistCandidatePlan(
            importResult.candidatePlan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let promotedPlanReplayValidationArtifact: ArtifactReference?
        if let planReplayValidation = qualification.planReplayValidation {
            promotedPlanReplayValidationArtifact = try await artifactStore.persistSymbolicPlannerPlanReplayValidation(
                planReplayValidation,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else {
            promotedPlanReplayValidationArtifact = nil
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "selected-certificate-missing-replay-validation",
                    message: "Selected solver certificate did not include a plan replay validation artifact to promote."
                )
            )
        }

        let verificationResult: XcircuiteCandidatePlanVerificationResult?
        if request.verifyPromotedPlan {
            verificationResult = try await XcircuiteCandidatePlanVerifier(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            ).verifyCandidatePlan(
                request: XcircuiteCandidatePlanVerificationRequest(runID: request.runID),
                projectRoot: projectRoot
            )
        } else {
            verificationResult = nil
        }
        if let verificationResult, !verificationResult.accepted {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "promoted-plan-verification-not-accepted",
                    message: "Promoted selected solver plan was written, but candidate-plan verification returned \(verificationResult.status)."
                )
            )
        }
        let status = promotionStatus(verificationResult: verificationResult, diagnostics: diagnostics)
        let promotion = XcircuiteSymbolicPlannerSolverFamilyPromotion(
            status: status,
            runID: request.runID,
            comparisonID: comparison.comparisonID,
            selectedCandidateIndex: selectedIndex,
            selectedToolID: qualification.toolID,
            sourceComparisonArtifact: comparisonInput.reference,
            sourceQualificationArtifact: qualificationArtifact,
            promotedCandidatePlanArtifact: promotedCandidatePlanArtifact,
            promotedSolverPlanArtifact: promotedSolverPlanArtifact,
            promotedPlanReplayValidationArtifact: promotedPlanReplayValidationArtifact,
            promotedPlanVerificationArtifact: verificationResult?.planVerificationArtifact,
            verificationStatus: verificationResult?.status,
            verificationAccepted: verificationResult?.accepted,
            diagnostics: diagnostics
        )
        let promotionArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyPromotion(
            promotion,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerSolverFamilyPromotionResult(
            promotion: promotion,
            promotionArtifact: promotionArtifact
        )
    }

    private func loadComparison(
        request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest,
        projectRoot: URL
    ) async throws -> ComparisonInput {
        let manifest = try await runManifest(runID: request.runID)
        let reference: ArtifactReference
        if let comparisonArtifactID = request.comparisonArtifactID {
            reference = try await uniqueVerifiedManifestArtifact(
                artifactID: comparisonArtifactID,
                field: "comparisonArtifactID",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else if let comparisonPath = request.comparisonPath {
            reference = try await verifiedProjectFileReference(
                path: comparisonPath,
                field: "comparisonPath",
                expectedFormat: .json,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else {
            reference = try await uniqueVerifiedManifestArtifact(
                artifactID: comparisonArtifactID(for: request.comparisonID),
                field: "comparisonArtifactID",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
        }
        let comparison = try await workspaceStore.readJSON(
            XcircuiteSymbolicPlannerSolverFamilyComparison.self,
            from: reference.path
        )
        return ComparisonInput(reference: reference, comparison: comparison)
    }

    private func loadQualification(
        artifact: ArtifactReference,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverQualificationResult {
        let integrity = LocalArtifactVerifier().verify(artifact, relativeTo: projectRoot)
        guard !integrity.isVerified else {
            return try await workspaceStore.readJSON(
                XcircuiteSymbolicPlannerSolverQualificationResult.self,
                from: artifact.path
            )
        }
        let status: FlowArtifactVerificationStatus = switch integrity.issues.first?.code {
        case .missingFile: .missingArtifact
        case .notRegularFile, .unreadableFile: .unreadableArtifact
        case .byteCountMismatch: .byteCountMismatch
        case .digestMismatch: .sha256Mismatch
        case .invalidLocation: .invalidPath
        case .unsupportedDigestAlgorithm: .invalidDigest
        case nil: .unreadableArtifact
        }
        let message = integrity.issues.map { issue in
            issue.detail ?? issue.location ?? issue.code.rawValue
        }.joined(separator: "; ")
        throw XcircuiteSymbolicPlannerSolverError.artifactIntegrityFailed(
            field: "qualificationArtifact",
            artifactID: artifact.id.rawValue,
            path: artifact.path,
            status: status,
            message: message
        )
    }

    private func promoteSolverPlanIfAvailable(
        qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        runID: String,
        projectRoot: URL,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) async throws -> ArtifactReference? {
        guard let solverPlanArtifact = qualification.solverResult.solverPlanArtifact else {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "selected-certificate-missing-solver-plan-artifact",
                    message: "Selected solver certificate did not include a raw solver plan artifact to promote."
                )
            )
            return nil
        }
        let solverPlanURL = try await workspaceStore.url(for: solverPlanArtifact.path)
        let solverPlanText: String
        do {
            solverPlanText = try String(contentsOf: solverPlanURL, encoding: .utf8)
        } catch {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "selected-solver-plan-read-failed",
                    message: "Could not read selected solver plan artifact \(solverPlanArtifact.path): \(error.localizedDescription)."
                )
            )
            return nil
        }
        return try await artifactStore.persistSymbolicPlannerSolverPlan(
            solverPlanText,
            runID: qualification.runID,
            projectRoot: projectRoot
        )
    }

    private func promotionStatus(
        verificationResult: XcircuiteCandidatePlanVerificationResult?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) -> String {
        if diagnostics.contains(where: { $0.severity == "error" }) {
            return "promoted-with-errors"
        }
        if let verificationResult, !verificationResult.accepted {
            return "promoted-with-verification-diagnostics"
        }
        if !diagnostics.isEmpty {
            return "promoted-with-warnings"
        }
        return "promoted"
    }

    private func runManifest(
        runID: String
    ) async throws -> FlowRunManifest {
        try await artifactReferenceResolver.runManifest(runID: runID)
    }

    private func uniqueVerifiedManifestArtifact(
        artifactID: String,
        field: String,
        expectedFormat: ArtifactFormat,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await artifactReferenceResolver.uniqueManifestArtifact(
            artifactID: artifactID,
            field: field,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func verifiedProjectFileReference(
        path: String,
        field: String,
        expectedFormat: ArtifactFormat,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await artifactReferenceResolver.projectFileReference(
            path: path,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func comparisonArtifactID(for comparisonID: String) -> String {
        "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyComparisonArtifactID)-\(String(comparisonID.prefix(80)))"
    }

    private struct ComparisonInput {
        var reference: ArtifactReference
        var comparison: XcircuiteSymbolicPlannerSolverFamilyComparison
    }
}
