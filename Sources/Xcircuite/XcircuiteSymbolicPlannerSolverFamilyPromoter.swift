import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyPromoter: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactReferenceResolver: XcircuiteSymbolicPlannerArtifactReferenceResolver

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactReferenceResolver = XcircuiteSymbolicPlannerArtifactReferenceResolver(
            workspaceStore: workspaceStore,
            fileReferenceVerifier: fileReferenceVerifier
        )
    }

    public func promote(
        request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverFamilyPromotionResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(request.comparisonID, kind: .artifactID)
        let comparisonInput = try loadComparison(request: request, projectRoot: projectRoot)
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
        let qualification = try loadQualification(
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
        let promotedSolverPlanArtifact = try promoteSolverPlanIfAvailable(
            qualification: qualification,
            runID: request.runID,
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        )
        let promotedCandidatePlanArtifact = try artifactStore.persistCandidatePlan(
            importResult.candidatePlan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let promotedPlanReplayValidationArtifact: XcircuiteFileReference?
        if let planReplayValidation = qualification.planReplayValidation {
            promotedPlanReplayValidationArtifact = try artifactStore.persistSymbolicPlannerPlanReplayValidation(
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
            verificationResult = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
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
            sourceComparisonArtifact: try requireFoundationArtifactReference(
                comparisonInput.reference,
                field: "promotion.sourceComparisonArtifact"
            ),
            sourceQualificationArtifact: qualificationArtifact,
            promotedCandidatePlanArtifact: try requireFoundationArtifactReference(
                promotedCandidatePlanArtifact,
                field: "promotion.promotedCandidatePlanArtifact"
            ),
            promotedSolverPlanArtifact: try promotedSolverPlanArtifact.map {
                try requireFoundationArtifactReference(
                    $0,
                    field: "promotion.promotedSolverPlanArtifact"
                )
            },
            promotedPlanReplayValidationArtifact: try promotedPlanReplayValidationArtifact.map {
                try requireFoundationArtifactReference(
                    $0,
                    field: "promotion.promotedPlanReplayValidationArtifact"
                )
            },
            promotedPlanVerificationArtifact: verificationResult?.planVerificationArtifact,
            verificationStatus: verificationResult?.status,
            verificationAccepted: verificationResult?.accepted,
            diagnostics: diagnostics
        )
        let promotionArtifact = try artifactStore.persistSymbolicPlannerSolverFamilyPromotion(
            promotion,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerSolverFamilyPromotionResult(
            promotion: promotion,
            promotionArtifact: try requireFoundationArtifactReference(
                promotionArtifact,
                field: "promotion.promotionArtifact"
            )
        )
    }

    private func loadComparison(
        request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest,
        projectRoot: URL
    ) throws -> ComparisonInput {
        let manifest = try runManifest(runID: request.runID, projectRoot: projectRoot)
        let reference: XcircuiteFileReference
        if let comparisonArtifactID = request.comparisonArtifactID {
            reference = try uniqueVerifiedManifestArtifact(
                artifactID: comparisonArtifactID,
                field: "comparisonArtifactID",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else if let comparisonPath = request.comparisonPath {
            reference = try verifiedProjectFileReference(
                path: comparisonPath,
                field: "comparisonPath",
                expectedFormat: .json,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else {
            reference = try uniqueVerifiedManifestArtifact(
                artifactID: comparisonArtifactID(for: request.comparisonID),
                field: "comparisonArtifactID",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
        }
        let comparison = try workspaceStore.readJSON(
            XcircuiteSymbolicPlannerSolverFamilyComparison.self,
            from: url(for: reference.path, projectRoot: projectRoot)
        )
        return ComparisonInput(reference: reference, comparison: comparison)
    }

    private func loadQualification(
        artifact: ArtifactReference,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerSolverQualificationResult {
        let integrity = LocalArtifactVerifier().verify(artifact, relativeTo: projectRoot)
        guard !integrity.isVerified else {
            return try workspaceStore.readJSON(
                XcircuiteSymbolicPlannerSolverQualificationResult.self,
                from: url(for: artifact.path, projectRoot: projectRoot)
            )
        }
        let status: XcircuiteFileReferenceIntegrityStatus = switch integrity.issues.first?.code {
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
    ) throws -> XcircuiteFileReference? {
        let solverPlanArtifact: ArtifactReference
        if let artifact = qualification.solverResult.solverPlanArtifact {
            solverPlanArtifact = artifact
        } else if let legacyArtifact = qualification.solverResult.importResult?.solverPlanArtifact {
            solverPlanArtifact = legacyArtifact
        } else {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "selected-certificate-missing-solver-plan-artifact",
                    message: "Selected solver certificate did not include a raw solver plan artifact to promote."
                )
            )
            return nil
        }
        let solverPlanURL = try url(for: solverPlanArtifact.path, projectRoot: projectRoot)
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
        return try artifactStore.persistSymbolicPlannerSolverPlan(
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
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteRunManifest {
        try artifactReferenceResolver.runManifest(runID: runID, projectRoot: projectRoot)
    }

    private func uniqueVerifiedManifestArtifact(
        artifactID: String,
        field: String,
        expectedFormat: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try artifactReferenceResolver.uniqueManifestArtifact(
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
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try artifactReferenceResolver.projectFileReference(
            path: path,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func verifiedArtifactReference(
        _ reference: XcircuiteFileReference,
        field: String,
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try artifactReferenceResolver.verifiedArtifactReference(
            reference,
            field: field,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func comparisonArtifactID(for comparisonID: String) -> String {
        "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyComparisonArtifactID)-\(String(comparisonID.prefix(80)))"
    }

    private func url(for path: String, projectRoot: URL) throws -> URL {
        return try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
    }

    private struct ComparisonInput {
        var reference: XcircuiteFileReference
        var comparison: XcircuiteSymbolicPlannerSolverFamilyComparison
    }
}
