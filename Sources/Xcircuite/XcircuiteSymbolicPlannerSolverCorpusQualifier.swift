import Foundation
import ToolQualification
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverCorpusQualifier: Sendable {
    private let artifactStore: XcircuitePlanningArtifactStore
    private let caseQualifier: XcircuiteSymbolicPlannerSolverQualifier?
    private let coverageTagValidator: XcircuiteSymbolicPlannerCoverageTagValidator

    public init(
        artifactStore: XcircuitePlanningArtifactStore,
        caseQualifier: XcircuiteSymbolicPlannerSolverQualifier? = nil,
        coverageTagValidator: XcircuiteSymbolicPlannerCoverageTagValidator = XcircuiteSymbolicPlannerCoverageTagValidator()
    ) {
        self.artifactStore = artifactStore
        self.caseQualifier = caseQualifier
        self.coverageTagValidator = coverageTagValidator
    }

    public func qualify(
        request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverCorpusQualificationResult {
        let identifierValidator = FlowIdentifierValidator()
        try identifierValidator.validate(request.suiteID, kind: .artifactID)
        for coverageTag in request.requiredCoverageTags {
            try identifierValidator.validate(coverageTag, kind: .artifactID)
        }
        try coverageTagValidator.validateImplementedCoverageTags(request.requiredCoverageTags)
        guard !request.cases.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.emptyQualificationCorpus
        }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let caseQualifier = caseQualifier ?? XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        let suiteSpecArtifact = try await artifactStore.persistSymbolicPlannerSolverQualificationCorpusSuiteSpec(
            XcircuiteSymbolicPlannerSolverCorpusSuiteSpec(request: request),
            projectRoot: projectRoot
        )

        var caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult] = []
        for corpusCase in request.cases {
            try identifierValidator.validate(corpusCase.caseID, kind: .artifactID)
            for coverageTag in corpusCase.coverageTags {
                try identifierValidator.validate(coverageTag, kind: .artifactID)
            }
            try coverageTagValidator.validateImplementedCoverageTags(corpusCase.coverageTags)
            let qualification = try await caseQualifier.qualify(
                request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                    runID: corpusCase.runID,
                    toolID: request.toolID,
                    executablePath: request.executablePath,
                    arguments: request.arguments,
                    timeoutSeconds: request.timeoutSeconds,
                    expectedActionIDs: corpusCase.expectedActionIDs,
                    requireGoalCoverage: corpusCase.requireGoalCoverage,
                    requireOptimality: corpusCase.requireOptimality,
                    maximumSolverCost: corpusCase.maximumSolverCost,
                    requireProofValidation: request.requireProofValidation,
                    policyID: request.policyID,
                    domainArtifactID: corpusCase.domainArtifactID,
                    domainPath: corpusCase.domainPath,
                    problemArtifactID: corpusCase.problemArtifactID,
                    problemPath: corpusCase.problemPath,
                    pddlExportArtifactID: corpusCase.pddlExportArtifactID,
                    pddlExportPath: corpusCase.pddlExportPath,
                    workingDirectoryPath: corpusCase.workingDirectoryPath,
                    solverPlanOutputPath: corpusCase.solverPlanOutputPath,
                    proofArtifactID: corpusCase.proofArtifactID,
                    proofPath: corpusCase.proofPath,
                    proofCheckerExecutablePath: request.proofCheckerExecutablePath,
                    proofCheckerArguments: request.proofCheckerArguments,
                    proofCheckerTimeoutSeconds: request.proofCheckerTimeoutSeconds,
                    proofCheckerWorkingDirectoryPath: corpusCase.proofCheckerWorkingDirectoryPath
                        ?? request.proofCheckerWorkingDirectoryPath
                ),
                projectRoot: projectRoot
            )
            let failureCodes = qualification.diagnostics
                .filter { $0.severity == "error" }
                .map(\.code)
            caseResults.append(
                XcircuiteSymbolicPlannerSolverCorpusCaseResult(
                    caseID: corpusCase.caseID,
                    runID: corpusCase.runID,
                    status: qualification.status,
                    expectedActionIDs: corpusCase.expectedActionIDs,
                    observedActionIDs: qualification.observedActionIDs,
                    coverageTags: corpusCase.coverageTags,
                    goalCoverageStatus: qualification.goalCoverageStatus,
                    missingGoalAtoms: qualification.missingGoalAtoms,
                    failureCodes: failureCodes,
                    qualificationArtifact: qualification.qualificationArtifact,
                    planVerificationArtifact: qualification.planVerificationArtifact
                )
            )
        }

        let coverageTagCounts = makeCoverageTagCounts(caseResults)
        let coveredCoverageTags = coverageTagCounts.keys.sorted()
        let missingRequiredCoverageTags = missingRequiredCoverageTags(
            requiredCoverageTags: request.requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags
        )
        let status = caseResults.allSatisfy { $0.status == "qualified" } && missingRequiredCoverageTags.isEmpty
            ? "qualified"
            : "failed"
        let result = makeResult(
            suiteID: request.suiteID,
            status: status,
            toolID: request.toolID,
            policyID: request.policyID,
            caseResults: caseResults,
            requiredCoverageTags: request.requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags,
            missingRequiredCoverageTags: missingRequiredCoverageTags,
            coverageTagCounts: coverageTagCounts,
            suiteSpecArtifact: suiteSpecArtifact,
            corpusArtifact: nil
        )
        let corpusArtifact = try await artifactStore.persistSymbolicPlannerSolverQualificationCorpus(
            result,
            projectRoot: projectRoot
        )
        return makeResult(
            suiteID: request.suiteID,
            status: status,
            toolID: request.toolID,
            policyID: request.policyID,
            caseResults: caseResults,
            requiredCoverageTags: request.requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags,
            missingRequiredCoverageTags: missingRequiredCoverageTags,
            coverageTagCounts: coverageTagCounts,
            suiteSpecArtifact: suiteSpecArtifact,
            corpusArtifact: corpusArtifact
        )
    }

    private func makeResult(
        suiteID: String,
        status: String,
        toolID: String,
        policyID: String,
        caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult],
        requiredCoverageTags: [String],
        coveredCoverageTags: [String],
        missingRequiredCoverageTags: [String],
        coverageTagCounts: [String: Int],
        suiteSpecArtifact: ArtifactReference?,
        corpusArtifact: ArtifactReference?
    ) -> XcircuiteSymbolicPlannerSolverCorpusQualificationResult {
        var failureCodes = unique(caseResults.flatMap(\.failureCodes))
        if !missingRequiredCoverageTags.isEmpty {
            failureCodes = unique(failureCodes + ["required-coverage-missing"])
        }
        let qualifiedCaseCount = caseResults.filter { $0.status == "qualified" }.count
        let failedCaseCount = caseResults.count - qualifiedCaseCount
        let healthStatus: ToolHealthStatus = status == "qualified" ? .passed : .failed
        let requiredCoverageTags = unique(requiredCoverageTags)
        let evidence = ToolEvidence(
            evidenceID: "\(toolID)-symbolic-planner-corpus-\(suiteID)",
            kind: .corpus,
            artifact: corpusArtifact ?? suiteSpecArtifact,
            checkedAt: Date()
        )
        let toolHealth = ToolHealthCheckResult(
            toolID: toolID,
            status: healthStatus,
            diagnostics: failureCodes.map { code in
                ToolDiagnostic(
                    severity: .error,
                    code: code,
                    message: "Symbolic planner corpus qualification observed failure code \(code)."
                )
            },
            evidence: [evidence]
        )
        return XcircuiteSymbolicPlannerSolverCorpusQualificationResult(
            suiteID: suiteID,
            status: status,
            toolID: toolID,
            policyID: policyID,
            caseResults: caseResults,
            qualifiedCaseCount: qualifiedCaseCount,
            failedCaseCount: failedCaseCount,
            requiredCoverageTags: requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags,
            missingRequiredCoverageTags: missingRequiredCoverageTags,
            coverageTagCounts: coverageTagCounts,
            failureCodes: failureCodes,
            suiteSpecArtifact: suiteSpecArtifact,
            corpusArtifact: corpusArtifact,
            toolHealth: toolHealth
        )
    }

    private func makeCoverageTagCounts(_ caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for caseResult in caseResults where caseResult.status == "qualified" {
            for coverageTag in unique(caseResult.coverageTags) {
                counts[coverageTag, default: 0] += 1
            }
        }
        return counts
    }

    private func missingRequiredCoverageTags(
        requiredCoverageTags: [String],
        coveredCoverageTags: [String]
    ) -> [String] {
        let covered = Set(coveredCoverageTags)
        return unique(requiredCoverageTags).filter { !covered.contains($0) }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
import CircuiteFoundation
