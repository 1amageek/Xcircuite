import Foundation
import ToolQualification
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyComparator: Sendable {
    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactReferenceResolver: XcircuiteSymbolicPlannerArtifactReferenceResolver

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.artifactReferenceResolver = XcircuiteSymbolicPlannerArtifactReferenceResolver(
            packageStore: packageStore,
            fileReferenceVerifier: fileReferenceVerifier
        )
    }

    public func compare(
        request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerSolverFamilyComparisonResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(request.comparisonID, kind: .artifactID)
        guard !request.qualificationArtifactIDs.isEmpty || !request.qualificationPaths.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.emptySolverFamilyComparison
        }

        let inputs = try qualificationInputs(request: request, projectRoot: projectRoot)
        var candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult] = []
        for (index, input) in inputs.enumerated() {
            guard input.qualification.runID == request.runID else {
                throw XcircuiteSymbolicPlannerSolverError.qualificationRunMismatch(
                    expected: request.runID,
                    actual: input.qualification.runID
                )
            }
            candidates.append(
                makeCandidate(
                    index: index,
                    qualification: input.qualification,
                    fallbackQualificationArtifact: input.reference
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
        let qualifiedCandidateCount = selectedCandidates.filter { $0.qualificationStatus == "qualified" }.count
        let failedCandidateCount = selectedCandidates.count - qualifiedCandidateCount
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        if qualifiedCandidateCount == 0 {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "no-qualified-solver-certificate",
                    message: "Solver family comparison did not find a qualified certificate; the highest-scoring failed certificate was selected for inspection."
                )
            )
        }
        let status = selectedCandidate.qualificationStatus == "qualified"
            ? "selected-qualified"
            : "selected-unqualified"
        let comparison = XcircuiteSymbolicPlannerSolverFamilyComparison(
            status: status,
            runID: request.runID,
            comparisonID: request.comparisonID,
            selectionPolicy: request.selectionPolicy,
            requestedQualificationArtifactIDs: request.qualificationArtifactIDs,
            requestedQualificationPaths: request.qualificationPaths,
            selectedCandidateIndex: selectedIndex,
            selectedToolID: selectedCandidate.toolID,
            selectedQualificationArtifact: selectedCandidate.qualificationArtifact,
            candidateCount: selectedCandidates.count,
            qualifiedCandidateCount: qualifiedCandidateCount,
            failedCandidateCount: failedCandidateCount,
            candidates: selectedCandidates,
            diagnostics: diagnostics
        )
        let comparisonArtifact = try artifactStore.persistSymbolicPlannerSolverFamilyComparison(
            comparison,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerSolverFamilyComparisonResult(
            comparison: comparison,
            comparisonArtifact: try requireFoundationArtifactReference(
                comparisonArtifact,
                field: "comparison.comparisonArtifact"
            )
        )
    }

    private func qualificationInputs(
        request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest,
        projectRoot: URL
    ) throws -> [QualificationInput] {
        let manifest = try artifactReferenceResolver.runManifest(
            runID: request.runID,
            projectRoot: projectRoot
        )
        var inputs: [QualificationInput] = []
        for artifactID in request.qualificationArtifactIDs {
            let reference = try artifactReferenceResolver.uniqueManifestArtifact(
                artifactID: artifactID,
                field: "qualificationArtifact",
                expectedFormat: .json,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let qualification = try packageStore.readJSON(
                XcircuiteSymbolicPlannerSolverQualificationResult.self,
                from: packageStore.url(forProjectRelativePath: reference.path, inProjectAt: projectRoot)
            )
            inputs.append(
                QualificationInput(
                    reference: try requireFoundationArtifactReference(
                        reference,
                        field: "comparison.qualificationArtifact"
                    ),
                    qualification: qualification
                )
            )
        }
        for path in request.qualificationPaths {
            let reference = try artifactReferenceResolver.projectFileReference(
                path: path,
                field: "qualificationArtifact",
                expectedFormat: .json,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let qualification = try packageStore.readJSON(
                XcircuiteSymbolicPlannerSolverQualificationResult.self,
                from: packageStore.url(forProjectRelativePath: reference.path, inProjectAt: projectRoot)
            )
            inputs.append(
                QualificationInput(
                    reference: try requireFoundationArtifactReference(
                        reference,
                        field: "comparison.qualificationArtifact"
                    ),
                    qualification: qualification
                )
            )
        }
        return inputs
    }

    private func makeCandidate(
        index: Int,
        qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        fallbackQualificationArtifact: ArtifactReference?
    ) -> XcircuiteSymbolicPlannerSolverFamilyCandidateResult {
        let missingExpectedActionIDs = missingExpectedActions(qualification)
        let evaluatedCost = evaluatedCost(qualification)
        let score = scoreComponents(
            qualification: qualification,
            missingExpectedActionIDs: missingExpectedActionIDs,
            evaluatedCost: evaluatedCost,
            candidateIndex: index
        )
        return XcircuiteSymbolicPlannerSolverFamilyCandidateResult(
            candidateIndex: index,
            status: qualification.status,
            selected: false,
            selectionScore: score.reduce(0) { $0 + $1.contribution },
            scoreComponents: score,
            toolID: qualification.toolID,
            qualificationStatus: qualification.status,
            toolHealthStatus: qualification.toolHealth.status.rawValue,
            solverRunStatus: qualification.solverResult.status,
            expectedActionIDs: qualification.expectedActionIDs,
            observedActionIDs: qualification.observedActionIDs,
            missingExpectedActionIDs: missingExpectedActionIDs,
            goalCoverageStatus: qualification.goalCoverageStatus,
            missingGoalAtoms: qualification.missingGoalAtoms,
            planReplayStatus: qualification.planReplayValidation?.status,
            proofValidationStatus: qualification.proofValidation?.status
                ?? qualification.nativeCertificate?.certificate?.proofStatus,
            optimalityStatus: qualification.nativeCertificate?.certificate?.optimalityStatus
                ?? qualification.solverMetadata?.optimalityStatus,
            evaluatedCost: evaluatedCost,
            maximumSolverCost: qualification.maximumSolverCost,
            solverPlanLength: solverPlanLength(qualification),
            solverExitCode: qualification.solverResult.exitCode,
            didTimeout: qualification.solverResult.didTimeout,
            didCancel: qualification.solverResult.didCancel,
            qualificationArtifact: fallbackQualificationArtifact ?? qualification.qualificationArtifact,
            nativeCertificateArtifact: qualification.nativeCertificateArtifact,
            planVerificationArtifact: qualification.planVerificationArtifact,
            diagnostics: qualification.diagnostics
        )
    }

    private func missingExpectedActions(
        _ qualification: XcircuiteSymbolicPlannerSolverQualificationResult
    ) -> [String] {
        let observed = Set(qualification.observedActionIDs)
        return qualification.expectedActionIDs.filter { !observed.contains($0) }
    }

    private func evaluatedCost(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Double? {
        if let cost = qualification.planCostEvaluation?.evaluatedCost {
            return cost
        }
        if let cost = qualification.planReplayValidation?.evaluatedCost {
            return cost
        }
        if let cost = qualification.nativeCertificate?.certificate?.planCost {
            return cost
        }
        return qualification.solverMetadata?.planCost
    }

    private func solverPlanLength(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Int? {
        if let planLength = qualification.planCostEvaluation?.planLength {
            return planLength
        }
        if let planLength = qualification.nativeCertificate?.certificate?.planLength {
            return planLength
        }
        if let planLength = qualification.solverMetadata?.planLength {
            return planLength
        }
        return qualification.planReplayValidation?.steps.count
    }

    private func selectedCandidateIndex(_ candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult]) -> Int {
        var selectedIndex = 0
        for index in candidates.indices.dropFirst() where candidates[index].selectionScore > candidates[selectedIndex].selectionScore {
            selectedIndex = index
        }
        return selectedIndex
    }

    private func scoreComponents(
        qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        missingExpectedActionIDs: [String],
        evaluatedCost: Double?,
        candidateIndex: Int
    ) -> [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent] {
        var components: [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent] = []
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "qualification-status",
                contribution: qualification.status == "qualified" ? 10_000 : -10_000,
                reason: "Qualified certificates are preferred over failed certificates."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "tool-health",
                contribution: toolHealthContribution(qualification.toolHealth.status),
                reason: "ToolQualification health gates are treated as certificate-level trust evidence."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "solver-process",
                contribution: solverProcessContribution(qualification.solverResult),
                reason: "A solver process that completed without timeout or cancellation is preferred."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "plan-replay",
                contribution: planReplayContribution(qualification.planReplayValidation?.status),
                reason: "Replay validation proves that imported symbolic actions satisfy preconditions and goals."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "goal-coverage",
                contribution: goalCoverageContribution(qualification),
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
                contribution: proofValidationContribution(qualification),
                reason: "Validated proof artifacts are preferred when the qualification policy requires proof checking."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "native-certificate",
                contribution: nativeCertificateContribution(qualification),
                reason: "Parsed native solver certificates provide structured solver-specific optimality and proof evidence."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "optimality",
                contribution: optimalityContribution(qualification),
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
                contribution: costBoundContribution(qualification: qualification, evaluatedCost: evaluatedCost),
                reason: "Configured maximum solver cost is preserved as an explicit selection signal."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent(
                termID: "diagnostics",
                contribution: diagnosticsContribution(qualification.diagnostics),
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

    private func toolHealthContribution(_ status: ToolHealthStatus) -> Int {
        switch status {
        case .passed:
            3_000
        case .blocked:
            -1_500
        case .failed:
            -3_000
        case .notChecked:
            -500
        }
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

    private func goalCoverageContribution(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Int {
        if qualification.goalCoverageStatus == "covered" {
            return 3_000
        }
        if qualification.requireGoalCoverage {
            return -2_000 - (250 * qualification.missingGoalAtoms.count)
        }
        return -250 * qualification.missingGoalAtoms.count
    }

    private func proofValidationContribution(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Int {
        guard qualification.requireProofValidation else {
            if qualification.proofValidation?.status == "validated" {
                return 250
            }
            return qualification.nativeCertificate?.certificate?.proofStatus == "validated" ? 150 : 0
        }
        if qualification.proofValidation?.status == "validated" {
            return 1_000
        }
        return qualification.nativeCertificate?.certificate?.proofStatus == "validated" ? 500 : -1_000
    }

    private func nativeCertificateContribution(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Int {
        guard let certificate = qualification.nativeCertificate else {
            return qualification.requireNativeCertificate ? -1_000 : 0
        }
        if certificate.status != "parsed" {
            return qualification.requireNativeCertificate ? -1_500 : -250
        }
        let errorCount = certificate.diagnostics.filter { $0.severity == "error" }.count
        let claimCount = certificate.certificate?.claims.count ?? 0
        return 500 + min(500, claimCount * 50) - (errorCount * 250)
    }

    private func optimalityContribution(_ qualification: XcircuiteSymbolicPlannerSolverQualificationResult) -> Int {
        let optimalityStatus = qualification.nativeCertificate?.certificate?.optimalityStatus
            ?? qualification.solverMetadata?.optimalityStatus
        guard optimalityStatus == "optimal" else {
            return qualification.requireOptimality ? -750 : 0
        }
        return qualification.requireOptimality ? 750 : 250
    }

    private func costContribution(_ cost: Double?) -> Int {
        guard let cost, cost.isFinite else {
            return -100
        }
        return 1_000 - Int((cost * 10).rounded())
    }

    private func costBoundContribution(
        qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        evaluatedCost: Double?
    ) -> Int {
        guard let maximumSolverCost = qualification.maximumSolverCost else {
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

    private struct QualificationInput {
        var reference: ArtifactReference?
        var qualification: XcircuiteSymbolicPlannerSolverQualificationResult
    }
}
