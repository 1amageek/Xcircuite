import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct XcircuiteSymbolicPlannerSolverFamilySelector: Sendable {
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

    public func compare(
        request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverFamilyComparisonResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        try FlowIdentifierValidator().validate(request.comparisonID, kind: .artifactID)
        guard !request.validationArtifactIDs.isEmpty || !request.validationPaths.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.emptySolverFamilyComparison
        }

        let inputs = try await validationInputs(request: request, projectRoot: projectRoot)
        var candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult] = []
        for (index, input) in inputs.enumerated() {
            guard input.validation.runID == request.runID else {
                throw XcircuiteSymbolicPlannerSolverError.validationRunMismatch(
                    expected: request.runID,
                    actual: input.validation.runID
                )
            }
            candidates.append(
                makeCandidate(
                    index: index,
                    validation: input.validation,
                    fallbackValidationArtifact: input.reference
                )
            )
        }

        let selectedIndex = selectedCandidateIndex(candidates)
        let selectedCandidate = candidates[selectedIndex]
        let selectedCandidates = candidates.map { candidate in
            var updated = candidate
            updated.selected = candidate.candidateIndex == selectedIndex
            return updated
        }
        let passedCandidateCount = selectedCandidates.filter { $0.validationStatus == "passed" }.count
        let failedCandidateCount = selectedCandidates.count - passedCandidateCount
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        if passedCandidateCount == 0 {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "no-validated-solver-certificate",
                    message: "Solver family comparison did not find a validated certificate; the highest-scoring failed certificate was selected for inspection."
                )
            )
        }
        let status = selectedCandidate.validationStatus == "passed"
            ? "selected-passing"
            : "selected-failing"
        let comparison = XcircuiteSymbolicPlannerSolverFamilyComparison(
            status: status,
            runID: request.runID,
            comparisonID: request.comparisonID,
            selectionPolicy: request.selectionPolicy,
            requestedValidationArtifactIDs: request.validationArtifactIDs,
            requestedValidationPaths: request.validationPaths,
            selectedCandidateIndex: selectedIndex,
            selectedToolID: selectedCandidate.toolID,
            selectedValidationArtifact: selectedCandidate.validationArtifact,
            candidateCount: selectedCandidates.count,
            passedCandidateCount: passedCandidateCount,
            failedCandidateCount: failedCandidateCount,
            candidates: selectedCandidates,
            diagnostics: diagnostics
        )
        let comparisonArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyComparison(
            comparison,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerSolverFamilyComparisonResult(
            comparison: comparison,
            comparisonArtifact: comparisonArtifact
        )
    }

    private func validationInputs(
        request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest,
        projectRoot: URL
    ) async throws -> [ValidationInput] {
        let manifest = try await artifactReferenceResolver.runManifest(
            runID: request.runID
        )
        var inputs: [ValidationInput] = []
        for artifactID in request.validationArtifactIDs {
            let reference = try await artifactReferenceResolver.uniqueManifestArtifact(
                artifactID: artifactID,
                field: "validationArtifact",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let validation = try JSONDecoder().decode(
                XcircuiteSymbolicPlannerSolverValidationResult.self,
                from: await workspaceStore.loadArtifactContent(for: reference)
            )
            inputs.append(
                ValidationInput(
                    reference: reference,
                    validation: validation
                )
            )
        }
        for path in request.validationPaths {
            let reference = try await artifactReferenceResolver.projectFileReference(
                path: path,
                field: "validationArtifact",
                expectedFormat: .json,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let validation = try JSONDecoder().decode(
                XcircuiteSymbolicPlannerSolverValidationResult.self,
                from: await workspaceStore.loadArtifactContent(for: reference)
            )
            inputs.append(
                ValidationInput(
                    reference: reference,
                    validation: validation
                )
            )
        }
        return inputs
    }

    private func makeCandidate(
        index: Int,
        validation: XcircuiteSymbolicPlannerSolverValidationResult,
        fallbackValidationArtifact: ArtifactReference?
    ) -> XcircuiteSymbolicPlannerSolverFamilyCandidateResult {
        let missingExpectedActionIDs = missingExpectedActions(validation)
        let evaluatedCost = evaluatedCost(validation)
        let score = scoreComponents(
            validation: validation,
            missingExpectedActionIDs: missingExpectedActionIDs,
            evaluatedCost: evaluatedCost,
            candidateIndex: index
        )
        return XcircuiteSymbolicPlannerSolverFamilyCandidateResult(
            candidateIndex: index,
            status: validation.status,
            selected: false,
            selectionScore: score.reduce(0) { $0 + $1.contribution },
            scoreComponents: score,
            toolID: validation.toolID,
            validationStatus: validation.status,
            solverRunStatus: validation.solverResult.status,
            expectedActionIDs: validation.expectedActionIDs,
            observedActionIDs: validation.observedActionIDs,
            missingExpectedActionIDs: missingExpectedActionIDs,
            goalCoverageStatus: validation.goalCoverageStatus,
            missingGoalAtoms: validation.missingGoalAtoms,
            planReplayStatus: validation.planReplayValidation?.status,
            proofValidationStatus: validation.proofValidation?.status
                ?? validation.nativeCertificate?.certificate?.proofStatus,
            optimalityStatus: validation.nativeCertificate?.certificate?.optimalityStatus
                ?? validation.solverMetadata?.optimalityStatus,
            evaluatedCost: evaluatedCost,
            maximumSolverCost: validation.maximumSolverCost,
            solverPlanLength: solverPlanLength(validation),
            solverExitCode: validation.solverResult.exitCode,
            didTimeout: validation.solverResult.didTimeout,
            didCancel: validation.solverResult.didCancel,
            validationArtifact: fallbackValidationArtifact ?? validation.validationArtifact,
            nativeCertificateArtifact: validation.nativeCertificateArtifact,
            planVerificationArtifact: validation.planVerificationArtifact,
            diagnostics: validation.diagnostics
        )
    }

    private func missingExpectedActions(
        _ validation: XcircuiteSymbolicPlannerSolverValidationResult
    ) -> [String] {
        let observed = Set(validation.observedActionIDs)
        return validation.expectedActionIDs.filter { !observed.contains($0) }
    }

    private func evaluatedCost(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Double? {
        if let cost = validation.planCostEvaluation?.evaluatedCost {
            return cost
        }
        if let cost = validation.planReplayValidation?.evaluatedCost {
            return cost
        }
        if let cost = validation.nativeCertificate?.certificate?.planCost {
            return cost
        }
        return validation.solverMetadata?.planCost
    }

    private func solverPlanLength(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Int? {
        if let planLength = validation.planCostEvaluation?.planLength {
            return planLength
        }
        if let planLength = validation.nativeCertificate?.certificate?.planLength {
            return planLength
        }
        if let planLength = validation.solverMetadata?.planLength {
            return planLength
        }
        return validation.planReplayValidation?.steps.count
    }

    private func selectedCandidateIndex(_ candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult]) -> Int {
        var selectedIndex = 0
        for index in candidates.indices.dropFirst() where candidates[index].selectionScore > candidates[selectedIndex].selectionScore {
            selectedIndex = index
        }
        return selectedIndex
    }

    private func scoreComponents(
        validation: XcircuiteSymbolicPlannerSolverValidationResult,
        missingExpectedActionIDs: [String],
        evaluatedCost: Double?,
        candidateIndex: Int
    ) -> [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent] {
        var components: [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent] = []
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "validation-status",
                contribution: validation.status == "passed" ? 10_000 : -10_000,
                reason: "Validated certificates are preferred over failed certificates."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "solver-process",
                contribution: solverProcessContribution(validation.solverResult),
                reason: "A solver process that completed without timeout or cancellation is preferred."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "plan-replay",
                contribution: planReplayContribution(validation.planReplayValidation?.status),
                reason: "Replay validation proves that imported symbolic actions satisfy preconditions and goals."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "goal-coverage",
                contribution: goalCoverageContribution(validation),
                reason: "Goal coverage is required before a solver certificate can safely drive repair execution."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "expected-actions",
                contribution: missingExpectedActionIDs.isEmpty
                    ? 1_000
                    : -500 * missingExpectedActionIDs.count,
                reason: "Expected action coverage keeps solver output aligned with the requested repair contract."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "proof-validation",
                contribution: proofValidationContribution(validation),
                reason: "Validated proof artifacts are preferred when the validation policy requires proof checking."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "native-certificate",
                contribution: nativeCertificateContribution(validation),
                reason: "Parsed native solver certificates provide structured solver-specific optimality and proof evidence."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "optimality",
                contribution: optimalityContribution(validation),
                reason: "Optimality claims improve trust when they are required or available as solver metadata."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "cost",
                contribution: costContribution(evaluatedCost),
                reason: "Lower evaluated PDDL action cost is preferred after correctness gates pass."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "cost-bound",
                contribution: costBoundContribution(validation: validation, evaluatedCost: evaluatedCost),
                reason: "Configured maximum solver cost is preserved as an explicit selection signal."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "diagnostics",
                contribution: diagnosticsContribution(validation.diagnostics),
                reason: "Diagnostics reduce score in proportion to error and warning evidence."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "candidate-order",
                contribution: -candidateIndex,
                reason: "Stable input order breaks ties deterministically."
            )
        )
        return components
    }

    private func solverProcessContribution(_ result: XcircuiteSymbolicPlannerSolverResult) -> Int {
        if result.didTimeout || result.didCancel {
            return -2_000
        }
        if result.exitCode == 0 {
            return 1_000
        }
        return -1_000
    }

    private func planReplayContribution(_ status: String?) -> Int {
        guard let status else {
            return -500
        }
        return status == "validated" ? 2_000 : -2_000
    }

    private func goalCoverageContribution(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Int {
        if validation.goalCoverageStatus == "covered" {
            return 3_000
        }
        if validation.requireGoalCoverage {
            return -2_000 - (250 * validation.missingGoalAtoms.count)
        }
        return -250 * validation.missingGoalAtoms.count
    }

    private func proofValidationContribution(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Int {
        guard validation.requireProofValidation else {
            if validation.proofValidation?.status == "validated" {
                return 250
            }
            return validation.nativeCertificate?.certificate?.proofStatus == "validated" ? 150 : 0
        }
        if validation.proofValidation?.status == "validated" {
            return 1_000
        }
        return validation.nativeCertificate?.certificate?.proofStatus == "validated" ? 500 : -1_000
    }

    private func nativeCertificateContribution(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Int {
        guard let certificate = validation.nativeCertificate else {
            return validation.requireNativeCertificate ? -1_000 : 0
        }
        if certificate.status != "parsed" {
            return validation.requireNativeCertificate ? -1_500 : -250
        }
        let errorCount = certificate.diagnostics.filter { $0.severity == "error" }.count
        let claimCount = certificate.certificate?.claims.count ?? 0
        return 500 + min(500, claimCount * 50) - (errorCount * 250)
    }

    private func optimalityContribution(_ validation: XcircuiteSymbolicPlannerSolverValidationResult) -> Int {
        let optimalityStatus = validation.nativeCertificate?.certificate?.optimalityStatus
            ?? validation.solverMetadata?.optimalityStatus
        guard optimalityStatus == "optimal" else {
            return validation.requireOptimality ? -750 : 0
        }
        return validation.requireOptimality ? 750 : 250
    }

    private func costContribution(_ cost: Double?) -> Int {
        guard let cost, cost.isFinite else {
            return -100
        }
        return 1_000 - Int((cost * 10).rounded())
    }

    private func costBoundContribution(
        validation: XcircuiteSymbolicPlannerSolverValidationResult,
        evaluatedCost: Double?
    ) -> Int {
        guard let maximumSolverCost = validation.maximumSolverCost else {
            return 0
        }
        guard let evaluatedCost, evaluatedCost.isFinite else {
            return -500
        }
        return evaluatedCost <= maximumSolverCost ? 500 : -1_000
    }

    private func diagnosticsContribution(_ diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]) -> Int {
        let errorCount = diagnostics.filter { $0.severity == "error" }.count
        let warningCount = diagnostics.filter { $0.severity == "warning" }.count
        return (-250 * errorCount) + (-25 * warningCount)
    }

    private struct ValidationInput {
        var reference: ArtifactReference?
        var validation: XcircuiteSymbolicPlannerSolverValidationResult
    }
}
