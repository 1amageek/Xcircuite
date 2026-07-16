import Foundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverCorpusAssessor: Sendable {
    private let artifactStore: XcircuitePlanningArtifactStore
    private let caseValidator: XcircuiteSymbolicPlannerSolverValidator?
    private let coverageTagValidator: XcircuiteSymbolicPlannerCoverageTagValidator

    public init(
        artifactStore: XcircuitePlanningArtifactStore,
        caseValidator: XcircuiteSymbolicPlannerSolverValidator? = nil,
        coverageTagValidator: XcircuiteSymbolicPlannerCoverageTagValidator = XcircuiteSymbolicPlannerCoverageTagValidator()
    ) {
        self.artifactStore = artifactStore
        self.caseValidator = caseValidator
        self.coverageTagValidator = coverageTagValidator
    }

    public func assess(
        request: XcircuiteSymbolicPlannerSolverCorpusAssessmentRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverCorpusAssessment {
        let identifierValidator = FlowIdentifierValidator()
        try identifierValidator.validate(request.suiteID, kind: .artifactID)
        for coverageTag in request.requiredCoverageTags {
            try identifierValidator.validate(coverageTag, kind: .artifactID)
        }
        try coverageTagValidator.validateImplementedCoverageTags(request.requiredCoverageTags)
        guard !request.cases.isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.emptySolverCorpusAssessment
        }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let caseValidator = caseValidator ?? XcircuiteSymbolicPlannerSolverValidator(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        let suiteSpecArtifact = try await artifactStore.persistSymbolicPlannerSolverCorpusAssessmentSuiteSpec(
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
            let validation = try await caseValidator.validate(
                request: XcircuiteSymbolicPlannerSolverValidationRequest(
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
            let failureCodes = validation.diagnostics
                .filter { $0.severity == "error" }
                .map(\.code)
            caseResults.append(
                XcircuiteSymbolicPlannerSolverCorpusCaseResult(
                    caseID: corpusCase.caseID,
                    runID: corpusCase.runID,
                    status: validation.status,
                    expectedActionIDs: corpusCase.expectedActionIDs,
                    observedActionIDs: validation.observedActionIDs,
                    coverageTags: corpusCase.coverageTags,
                    goalCoverageStatus: validation.goalCoverageStatus,
                    missingGoalAtoms: validation.missingGoalAtoms,
                    failureCodes: failureCodes,
                    validationArtifact: validation.validationArtifact,
                    planVerificationArtifact: validation.planVerificationArtifact
                )
            )
        }

        let coverageTagCounts = makeCoverageTagCounts(caseResults)
        let coveredCoverageTags = coverageTagCounts.keys.sorted()
        let missingRequiredCoverageTags = missingRequiredCoverageTags(
            requiredCoverageTags: request.requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags
        )
        let status = caseResults.allSatisfy { $0.status == "passed" } && missingRequiredCoverageTags.isEmpty
            ? "passed"
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
        let corpusArtifact = try await artifactStore.persistSymbolicPlannerSolverCorpusAssessment(
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
    ) -> XcircuiteSymbolicPlannerSolverCorpusAssessment {
        var failureCodes = unique(caseResults.flatMap(\.failureCodes))
        if !missingRequiredCoverageTags.isEmpty {
            failureCodes = unique(failureCodes + ["required-coverage-missing"])
        }
        let passedCaseCount = caseResults.filter { $0.status == "passed" }.count
        let failedCaseCount = caseResults.count - passedCaseCount
        let requiredCoverageTags = unique(requiredCoverageTags)
        return XcircuiteSymbolicPlannerSolverCorpusAssessment(
            suiteID: suiteID,
            status: status,
            toolID: toolID,
            policyID: policyID,
            caseResults: caseResults,
            passedCaseCount: passedCaseCount,
            failedCaseCount: failedCaseCount,
            requiredCoverageTags: requiredCoverageTags,
            coveredCoverageTags: coveredCoverageTags,
            missingRequiredCoverageTags: missingRequiredCoverageTags,
            coverageTagCounts: coverageTagCounts,
            failureCodes: failureCodes,
            suiteSpecArtifact: suiteSpecArtifact,
            corpusArtifact: corpusArtifact
        )
    }

    private func makeCoverageTagCounts(_ caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for caseResult in caseResults where caseResult.status == "passed" {
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
