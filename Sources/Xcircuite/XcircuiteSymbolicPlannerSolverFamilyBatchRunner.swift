import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyBatchRunner: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let validator: XcircuiteSymbolicPlannerSolverValidator?
    private let comparator: XcircuiteSymbolicPlannerSolverFamilySelector?
    private let promoter: XcircuiteSymbolicPlannerSolverFamilyPromoter?

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        validator: XcircuiteSymbolicPlannerSolverValidator? = nil,
        comparator: XcircuiteSymbolicPlannerSolverFamilySelector? = nil,
        promoter: XcircuiteSymbolicPlannerSolverFamilyPromoter? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.validator = validator
        self.comparator = comparator
        self.promoter = promoter
    }

    public func run(
        request: XcircuiteSymbolicPlannerSolverFamilyBatchRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverFamilyBatchResult {
        let workspaceStore = self.workspaceStore
        let validator = validator ?? XcircuiteSymbolicPlannerSolverValidator(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        let comparator = comparator ?? XcircuiteSymbolicPlannerSolverFamilySelector(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        let promoter = promoter ?? XcircuiteSymbolicPlannerSolverFamilyPromoter(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        try FlowIdentifierValidator().validate(request.comparisonID, kind: .artifactID)
        guard !request.candidates.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.emptySolverFamilyComparison
        }
        try validateCandidates(request.candidates)

        var candidateResults: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateResult] = []
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        for (index, candidate) in request.candidates.enumerated() {
            let candidateID = try candidateIdentifier(
                requestedID: candidate.candidateID,
                toolID: candidate.toolID,
                index: index
            )
            var validation = try await validator.validate(
                request: candidate.validationRequest(runID: request.runID),
                projectRoot: projectRoot
            )
            let solverPlanArtifact = try await snapshotSolverPlanIfAvailable(
                validation: &validation,
                comparisonID: request.comparisonID,
                candidateID: candidateID,
                projectRoot: projectRoot
            )
            let nativeCertificateArtifact = try await snapshotNativeCertificateIfAvailable(
                validation: &validation,
                comparisonID: request.comparisonID,
                candidateID: candidateID,
                projectRoot: projectRoot
            )
            let validationArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyValidation(
            validation,
            runID: request.runID,
            comparisonID: request.comparisonID,
            candidateID: candidateID,
            projectRoot: projectRoot
            )
            validation = validation.attachingValidationArtifact(validationArtifact)
            candidateResults.append(
                XcircuiteSymbolicPlannerSolverFamilyBatchCandidateResult(
                    candidateIndex: index,
                    candidateID: candidateID,
                    toolID: validation.toolID,
                    validationStatus: validation.status,
                    validationArtifact: validationArtifact,
                    solverPlanArtifact: solverPlanArtifact,
                    nativeCertificateArtifact: nativeCertificateArtifact,
                    diagnostics: validation.diagnostics
                )
            )
        }

        let comparisonResult = try await comparator.compare(
            request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest(
                runID: request.runID,
                comparisonID: request.comparisonID,
                validationArtifactIDs: candidateResults.map(\.validationArtifact.artifactID),
                selectionPolicy: request.selectionPolicy
            ),
            projectRoot: projectRoot
        )
        let promotionResult = try await promoteIfRequested(
            request: request,
            comparisonArtifact: comparisonResult.comparisonArtifact,
            projectRoot: projectRoot,
            diagnostics: &diagnostics,
            promoter: promoter
        )
        let batchRun = XcircuiteSymbolicPlannerSolverFamilyBatchRun(
            status: batchStatus(
                comparison: comparisonResult.comparison,
                promotion: promotionResult?.promotion,
                diagnostics: diagnostics
            ),
            runID: request.runID,
            comparisonID: request.comparisonID,
            selectionPolicy: request.selectionPolicy,
            candidateCount: candidateResults.count,
            passedCandidateCount: candidateResults.filter { $0.validationStatus == "passed" }.count,
            failedCandidateCount: candidateResults.filter { $0.validationStatus != "passed" }.count,
            candidates: candidateResults,
            comparisonArtifact: comparisonResult.comparisonArtifact,
            promotionArtifact: promotionResult?.promotionArtifact,
            diagnostics: diagnostics
        )
        let batchArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyBatch(
            batchRun,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerSolverFamilyBatchResult(
            batchRun: batchRun,
            batchArtifact: batchArtifact,
            comparisonResult: comparisonResult,
            promotionResult: promotionResult
        )
    }

    private func snapshotSolverPlanIfAvailable(
        validation: inout XcircuiteSymbolicPlannerSolverValidationResult,
        comparisonID: String,
        candidateID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        guard let solverPlanArtifact = validation.solverResult.solverPlanArtifact else {
            return nil
        }
        let solverPlanURL = try await url(for: solverPlanArtifact.path)
        let solverPlanText = try String(contentsOf: solverPlanURL, encoding: .utf8)
        let snapshot = try await artifactStore.persistSymbolicPlannerSolverFamilySolverPlan(
            solverPlanText,
            runID: validation.runID,
            comparisonID: comparisonID,
            candidateID: candidateID,
            projectRoot: projectRoot
        )
        validation.solverResult.solverPlanArtifact = snapshot
        if var importResult = validation.solverResult.importResult {
            importResult.solverPlanArtifact = snapshot
            validation.solverResult.importResult = importResult
        }
        return snapshot
    }

    private func snapshotNativeCertificateIfAvailable(
        validation: inout XcircuiteSymbolicPlannerSolverValidationResult,
        comparisonID: String,
        candidateID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        guard let nativeCertificate = validation.nativeCertificate else {
            return nil
        }
        let snapshot = try await artifactStore.persistSymbolicPlannerSolverFamilyCertificate(
            nativeCertificate,
            runID: validation.runID,
            comparisonID: comparisonID,
            candidateID: candidateID,
            projectRoot: projectRoot
        )
        validation.nativeCertificateArtifact = snapshot
        return snapshot
    }

    private func promoteIfRequested(
        request: XcircuiteSymbolicPlannerSolverFamilyBatchRequest,
        comparisonArtifact: ArtifactReference,
        projectRoot: URL,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic],
        promoter: XcircuiteSymbolicPlannerSolverFamilyPromoter
    ) async throws -> XcircuiteSymbolicPlannerSolverFamilyPromotionResult? {
        guard request.promoteSelectedPlan else {
            return nil
        }
        do {
            return try await promoter.promote(
                request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                    runID: request.runID,
                    comparisonID: request.comparisonID,
                    comparisonArtifactID: comparisonArtifact.artifactID,
                    requirePassingValidation: request.requirePassingValidationForPromotion,
                    verifyPromotedPlan: request.verifyPromotedPlan
                ),
                projectRoot: projectRoot
            )
        } catch {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "solver-family-promotion-failed",
                    message: "Solver family batch comparison completed, but selected plan promotion failed: \(error.localizedDescription)."
                )
            )
            return nil
        }
    }

    private func batchStatus(
        comparison: XcircuiteSymbolicPlannerSolverFamilyComparison,
        promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) -> String {
        if diagnostics.contains(where: { $0.severity == "error" }) {
            return "completed-with-errors"
        }
        if let promotion {
            return promotion.status == "promoted"
                ? "completed-with-promotion"
                : "completed-with-promotion-diagnostics"
        }
        return comparison.status == "selected-passing"
            ? "completed-with-passing-selection"
            : "completed-with-failing-selection"
    }

    private func candidateIdentifier(requestedID: String?, toolID: String, index: Int) throws -> String {
        let rawSuffix = requestedID ?? toolID
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var sanitized = ""
        for scalar in rawSuffix.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.unicodeScalars.append(scalar)
            } else {
                sanitized.append("-")
            }
        }
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let suffix = trimmed.isEmpty ? "solver" : trimmed
        let candidateID = String("candidate-\(index)-\(suffix)".prefix(96))
        try FlowIdentifierValidator().validate(candidateID, kind: .artifactID)
        return candidateID
    }

    private func validateCandidates(
        _ candidates: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest]
    ) throws {
        let validator = FlowIdentifierValidator()
        var toolIDs: Set<String> = []
        for (index, candidate) in candidates.enumerated() {
            if let candidateID = candidate.candidateID {
                do {
                    try validator.validate(candidateID, kind: .artifactID)
                } catch {
                    throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateID(
                        index: index,
                        candidateID: candidateID
                    )
                }
            }
            do {
                try validator.validate(candidate.toolID, kind: .toolID)
            } catch {
                throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateToolID(
                    index: index,
                    toolID: candidate.toolID
                )
            }
            guard toolIDs.insert(candidate.toolID).inserted else {
                throw XcircuiteSymbolicPlannerSolverError.duplicateSolverFamilyCandidateToolID(
                    toolID: candidate.toolID
                )
            }
            guard !candidate.executablePath.isEmpty else {
                throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateExecutablePath(index: index)
            }
            guard candidate.timeoutSeconds.isFinite, candidate.timeoutSeconds > 0 else {
                throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateTimeout(
                    index: index,
                    timeoutSeconds: candidate.timeoutSeconds
                )
            }
            if candidate.requireProofValidation
                || candidate.proofCheckerExecutablePath != nil
                || candidate.proofArtifactID != nil
                || candidate.proofPath != nil {
                guard candidate.proofCheckerTimeoutSeconds.isFinite,
                      candidate.proofCheckerTimeoutSeconds > 0 else {
                    throw XcircuiteSymbolicPlannerSolverError.invalidProofCheckerTimeout(
                        candidate.proofCheckerTimeoutSeconds
                    )
                }
            }
            try validateArtifactID(candidate.domainArtifactID, field: "domainArtifactID", index: index, validator: validator)
            try validateArtifactID(candidate.problemArtifactID, field: "problemArtifactID", index: index, validator: validator)
            try validateArtifactID(candidate.pddlExportArtifactID, field: "pddlExportArtifactID", index: index, validator: validator)
            try validateArtifactID(candidate.certificateArtifactID, field: "certificateArtifactID", index: index, validator: validator)
            try validateArtifactID(candidate.proofArtifactID, field: "proofArtifactID", index: index, validator: validator)
            try validatePath(candidate.domainPath, field: "domainPath", index: index)
            try validatePath(candidate.problemPath, field: "problemPath", index: index)
            try validatePath(candidate.pddlExportPath, field: "pddlExportPath", index: index)
            try validatePath(candidate.workingDirectoryPath, field: "workingDirectoryPath", index: index)
            try validatePath(candidate.solverPlanOutputPath, field: "solverPlanOutputPath", index: index)
            try validatePath(candidate.certificatePath, field: "certificatePath", index: index)
            try validatePath(candidate.proofPath, field: "proofPath", index: index)
            try validatePath(
                candidate.proofCheckerWorkingDirectoryPath,
                field: "proofCheckerWorkingDirectoryPath",
                index: index
            )
        }
    }

    private func validateArtifactID(
        _ value: String?,
        field: String,
        index: Int,
        validator: FlowIdentifierValidator
    ) throws {
        guard let value else { return }
        do {
            try validator.validate(value, kind: .artifactID)
        } catch {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateReference(
                index: index,
                field: field,
                value: value
            )
        }
    }

    private func validatePath(_ value: String?, field: String, index: Int) throws {
        guard let value else { return }
        guard !value.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverFamilyCandidateReference(
                index: index,
                field: field,
                value: value
            )
        }
    }

    private func url(for path: String) async throws -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return try await workspaceStore.url(for: path)
    }
}
