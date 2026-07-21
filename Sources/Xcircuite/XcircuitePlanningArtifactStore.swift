import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct XcircuitePlanningArtifactStore: Sendable {
    public static let actionDomainArtifactID = "planning-action-domain-snapshot"
    public static let actionDomainRelativePath = "planning/action-domain-snapshot.json"
    public static let repairPlanFormulationArtifactID = "planning-repair-plan-formulation"
    public static let repairPlanFormulationRelativePath = "planning/repair-formulation.json"
    public static let problemArtifactID = "planning-problem"
    public static let problemRelativePath = "planning/problem.json"
    public static let planningProblemValidationArtifactID = "planning-problem-validation"
    public static let planningProblemValidationRelativePath = "planning/problem-validation.json"
    public static let problemTranslationAuditArtifactID = "planning-problem-translation-audit"
    public static let problemTranslationAuditRelativePath = "planning/problem-translation-audit.json"
    public static let candidatePlanArtifactID = "planning-candidate-plan"
    public static let candidatePlanRelativePath = "planning/candidate-plan.json"
    public static let generatedCandidatePlanDirectory = "planning/generated-candidate-plans"
    public static let symbolicPlannerTraceArtifactID = "planning-symbolic-planner-trace"
    public static let symbolicPlannerTraceRelativePath = "planning/symbolic-planner-trace.json"
    public static let generatedSymbolicPlannerTraceDirectory = "planning/generated-symbolic-planner-traces"
    public static let symbolicPlannerFamilyRunArtifactID = "planning-symbolic-planner-family-run"
    public static let symbolicPlannerFamilyRunRelativePath = "planning/symbolic-planner/family/family-run.json"
    public static let symbolicPlannerPDDLDomainArtifactID = "planning-symbolic-planner-pddl-domain"
    public static let symbolicPlannerPDDLDomainRelativePath = "planning/symbolic-planner/domain.pddl"
    public static let symbolicPlannerPDDLProblemArtifactID = "planning-symbolic-planner-pddl-problem"
    public static let symbolicPlannerPDDLProblemRelativePath = "planning/symbolic-planner/problem.pddl"
    public static let symbolicPlannerPDDLExportArtifactID = "planning-symbolic-planner-pddl-export"
    public static let symbolicPlannerPDDLExportRelativePath = "planning/symbolic-planner/pddl-export.json"
    public static let symbolicPlannerSolverPlanArtifactID = "planning-symbolic-planner-solver-plan"
    public static let symbolicPlannerSolverPlanRelativePath = "planning/symbolic-planner/solver-plan.txt"
    public static let symbolicPlannerSolverProofArtifactID = "planning-symbolic-planner-solver-proof"
    public static let symbolicPlannerSolverProofRelativePath = "planning/symbolic-planner/solver-proof.txt"
    public static let symbolicPlannerSolverCertificateArtifactID = "planning-symbolic-planner-solver-certificate"
    public static let symbolicPlannerSolverCertificateRelativePath = "planning/symbolic-planner/solver-certificate.json"
    public static let symbolicPlannerPlanReplayValidationArtifactID = "planning-symbolic-planner-plan-replay-validation"
    public static let symbolicPlannerPlanReplayValidationRelativePath = "planning/symbolic-planner/plan-replay-validation.json"
    public static let symbolicPlannerProofValidationArtifactID = "planning-symbolic-planner-proof-validation"
    public static let symbolicPlannerProofValidationRelativePath = "planning/symbolic-planner/proof-validation.json"
    public static let symbolicPlannerProofValidationStdoutArtifactID = "planning-symbolic-planner-proof-validation-stdout"
    public static let symbolicPlannerProofValidationStdoutRelativePath = "planning/symbolic-planner/proof-validation-stdout.txt"
    public static let symbolicPlannerProofValidationStderrArtifactID = "planning-symbolic-planner-proof-validation-stderr"
    public static let symbolicPlannerProofValidationStderrRelativePath = "planning/symbolic-planner/proof-validation-stderr.txt"
    public static let symbolicPlannerSolverRunArtifactID = "planning-symbolic-planner-solver-run"
    public static let symbolicPlannerSolverRunRelativePath = "planning/symbolic-planner/solver-run.json"
    public static let symbolicPlannerSolverStdoutArtifactID = "planning-symbolic-planner-solver-stdout"
    public static let symbolicPlannerSolverStdoutRelativePath = "planning/symbolic-planner/solver-stdout.txt"
    public static let symbolicPlannerSolverStderrArtifactID = "planning-symbolic-planner-solver-stderr"
    public static let symbolicPlannerSolverStderrRelativePath = "planning/symbolic-planner/solver-stderr.txt"
    public static let symbolicPlannerSolverValidationArtifactID = "planning-symbolic-planner-solver-validation"
    public static let symbolicPlannerSolverValidationRelativePath = "planning/symbolic-planner/solver-validation.json"
    public static let symbolicPlannerSolverFamilyComparisonArtifactID = "planning-symbolic-planner-solver-family-comparison"
    public static let symbolicPlannerSolverFamilyComparisonRelativePath = "planning/symbolic-planner/solver-family/solver-family-comparison.json"
    public static let symbolicPlannerSolverFamilyPromotionArtifactID = "planning-symbolic-planner-solver-family-promotion"
    public static let symbolicPlannerSolverFamilyPromotionRelativePath = "planning/symbolic-planner/solver-family/solver-family-promotion.json"
    public static let symbolicPlannerSolverFamilyBatchArtifactID = "planning-symbolic-planner-solver-family-batch"
    public static let symbolicPlannerSolverFamilyBatchRelativePath = "planning/symbolic-planner/solver-family/solver-family-batch.json"
    public static let symbolicPlannerSolverFamilyValidationArtifactID = "planning-symbolic-planner-solver-family-validation"
    public static let symbolicPlannerSolverFamilySolverPlanArtifactID = "planning-symbolic-planner-solver-family-solver-plan"
    public static let symbolicPlannerSolverFamilyCertificateArtifactID = "planning-symbolic-planner-solver-family-certificate"
    public static let symbolicPlannerInstalledSolverLaneArtifactID = "planning-symbolic-planner-installed-solver-lane"
    public static let symbolicPlannerInstalledSolverLaneRelativePath = "planning/symbolic-planner/installed-solver-lane.json"
    public static let symbolicPlannerSolverCorpusAssessmentSuiteSpecArtifactID = "planning-symbolic-planner-solver-corpus-assessment-suite-spec"
    public static let symbolicPlannerSolverCorpusAssessmentArtifactID = "planning-symbolic-planner-solver-corpus-assessment"
    public static let parameterCandidatesArtifactID = "planning-parameter-candidates"
    public static let parameterCandidatesRelativePath = "planning/parameter-candidates.jsonl"
    public static let parameterCandidateSearchTraceArtifactID = "planning-parameter-candidate-search-trace"
    public static let parameterCandidateSearchTraceRelativePath = "planning/parameter-candidate-search-trace.json"
    public static let parameterCandidateSelectionTraceArtifactID = "planning-parameter-candidate-selection-trace"
    public static let parameterCandidateSelectionTraceRelativePath = "planning/parameter-candidate-selection-trace.json"
    public static let rejectedPlansArtifactID = "planning-rejected-plans"
    public static let rejectedPlansRelativePath = "planning/rejected-plans.jsonl"
    public static let planVerificationArtifactID = "planning-plan-verification"
    public static let planVerificationDirectory = "planning/plan-verification"
    public static let planExecutionArtifactID = "planning-plan-execution"
    public static let planExecutionDirectory = "planning/plan-execution"
    public static let candidateCycleHistorySummaryArtifactID = "planning-candidate-cycle-history-summary"
    public static let numericRepairLoopArtifactID = "planning-numeric-repair-loop"
    public static let numericRepairLoopRelativePath = "planning/numeric-repair-loop.json"
    public static let metricThresholdProfileArtifactID = "planning-metric-threshold-profile"
    public static let metricThresholdProfileRelativePath = "planning/metric-threshold-profile.json"
    public static let costCalibrationArtifactID = "planning-cost-calibration"
    public static let costCalibrationRelativePath = "planning/cost-calibration.json"
    public static let paretoCandidatesArtifactID = "planning-pareto-candidates"
    public static let paretoCandidatesRelativePath = "planning/pareto-candidates.jsonl"
    public static let improvementLoopArtifactID = "planning-improvement-loop"
    public static let improvementLoopRelativePath = "planning/improvement-loop.json"
    public static let rejectedFeedbackLearningReportArtifactID = "planning-rejected-feedback-learning-report"
    public static let rejectedFeedbackLearningReportRelativePath = "planning/rejected-feedback-learning-report.json"

    private let workspaceStore: XcircuiteWorkspaceStore
    private let snapshotBuilder: XcircuiteActionDomainSnapshotBuilder

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        snapshotBuilder: XcircuiteActionDomainSnapshotBuilder = XcircuiteActionDomainSnapshotBuilder()
    ) {
        self.workspaceStore = workspaceStore
        self.snapshotBuilder = snapshotBuilder
    }

    static func generatedCandidatePlanReferences(
        in manifest: FlowRunManifest
    ) -> [ArtifactReference] {
        let pathPrefix = ".xcircuite/runs/\(manifest.runID)/\(generatedCandidatePlanDirectory)/"
        return manifest.artifacts.filter {
            $0.path.hasPrefix(pathPrefix)
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
    }

    public func persistActionDomainSnapshot(runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try await persistActionDomainSnapshot(runID: runID, projectRoot: projectRoot, generatedAt: Self.currentTimestamp())
    }

    public func persistActionDomainSnapshot(runID: String, projectRoot: URL, generatedAt: String) async throws -> ArtifactReference {
        let snapshot = try snapshotBuilder.snapshot(runID: runID, generatedAt: generatedAt)
        return try await persistRunJSON(snapshot, id: Self.actionDomainArtifactID, path: Self.actionDomainRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistRepairPlanFormulation(_ value: XcircuiteRepairPlanFormulation, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.repairPlanFormulationArtifactID, path: Self.repairPlanFormulationRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func persistPlanningProblem(_ value: XcircuiteCircuitPlanningProblem, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.problemArtifactID, path: Self.problemRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistPlanningProblemValidation(_ value: XcircuitePlanningProblemValidation, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.planningProblemValidationArtifactID, path: Self.planningProblemValidationRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistProblemTranslationAudit(
        _ value: XcircuiteProblemTranslationAudit,
        runID: String,
        projectRoot: URL,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistRunData(
            encoder.encode(value),
            id: Self.problemTranslationAuditArtifactID,
            path: Self.problemTranslationAuditRelativePath,
            format: .json,
            runID: runID,
            projectRoot: projectRoot,
            mode: mode
        )
    }

    public func persistParameterCandidates(_ values: [XcircuiteParameterCandidate], runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        if let mismatch = values.first(where: { $0.runID != runID }) {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: mismatch.runID)
        }
        return try await persistRunText(try jsonLines(values), id: Self.parameterCandidatesArtifactID, path: Self.parameterCandidatesRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func appendRejectedPlan(_ record: XcircuiteRejectedPlanRecord, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(record.runID, expected: runID)
        let store = try resolvedWorkspaceStore(projectRoot: projectRoot)
        let path = runPath(Self.rejectedPlansRelativePath, runID: runID)
        let locator = try artifactLocator(path: path, format: .text)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedRecord = try encoder.encode(record)
        for attempt in 0..<8 {
            let existing = try await store.loadArtifactContent(at: locator) ?? Data()
            let records = try decodeRejectedPlans(existing, runID: runID)
            guard !records.contains(where: { $0.rejectionID == record.rejectionID }) else {
                throw XcircuitePlanningArtifactError.duplicateRejectedPlan(rejectionID: record.rejectionID)
            }
            var updated = existing
            if !updated.isEmpty, updated.last != 0x0A { updated.append(0x0A) }
            updated.append(encodedRecord)
            updated.append(0x0A)
            do {
                return try await store.persistArtifact(
                    content: updated,
                    id: try ArtifactID(rawValue: Self.rejectedPlansArtifactID),
                    locator: locator,
                    runID: runID,
                    mode: .appendOnly
                )
            } catch XcircuiteWorkspaceStoreError.appendOnlyArtifactConflict where attempt < 7 {
                continue
            }
        }
        throw XcircuitePlanningArtifactError.concurrentAppendConflict(path: path)
    }

    public func persistParameterCandidateSearchTrace(_ value: XcircuiteParameterCandidateSearchTrace, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.parameterCandidateSearchTraceArtifactID, path: Self.parameterCandidateSearchTraceRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistParameterCandidateSelectionTrace(_ value: XcircuiteParameterCandidateSelectionTrace, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        return try await persistRunJSON(value, id: Self.parameterCandidateSelectionTraceArtifactID, path: Self.parameterCandidateSelectionTraceRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func persistCandidatePlan(_ value: XcircuiteCandidatePlan, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.candidatePlanArtifactID, path: Self.candidatePlanRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistGeneratedCandidatePlan(
        _ value: XcircuiteCandidatePlan,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistContentAddressedRunJSON(
            value,
            identity: "generated-candidate-plan:\(runID):\(value.planID)",
            directory: Self.generatedCandidatePlanDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func persistCandidatePlanSnapshot(
        _ value: XcircuiteCandidatePlan,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistImmutableRunJSON(
            value,
            id: ArtifactID(
                stableKey: "candidate-plan-snapshot:\(runID):\(value.planID)"
            ).rawValue,
            directory: "planning/candidate-plans",
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func persistSymbolicPlannerTrace(_ value: XcircuiteSymbolicPlannerTrace, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.symbolicPlannerTraceArtifactID, path: Self.symbolicPlannerTraceRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistGeneratedSymbolicPlannerTrace(
        _ value: XcircuiteSymbolicPlannerTrace,
        planID: String,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistContentAddressedRunJSON(
            value,
            identity: "generated-symbolic-planner-trace:\(runID):\(planID)",
            directory: Self.generatedSymbolicPlannerTraceDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func persistSymbolicPlannerFamilyRun(_ value: XcircuiteSymbolicPlannerFamilyRun, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        try FlowIdentifierValidator().validate(value.familyRunID, kind: .artifactID)
        let path = "planning/symbolic-planner/family/\(value.familyRunID)/family-run.json"
        let id = "\(Self.symbolicPlannerFamilyRunArtifactID)-\(String(value.familyRunID.prefix(80)))"
        return try await persistRunJSON(value, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerPDDLExport(_ value: XcircuiteSymbolicPlannerPDDLExport, runID: String, projectRoot: URL) async throws -> XcircuiteSymbolicPlannerPDDLArtifactSet {
        try validateRun(value.runID, expected: runID)
        let domain = try await persistRunText(value.domainPDDL, id: Self.symbolicPlannerPDDLDomainArtifactID, path: Self.symbolicPlannerPDDLDomainRelativePath, runID: runID, projectRoot: projectRoot)
        let problem = try await persistRunText(value.problemPDDL, id: Self.symbolicPlannerPDDLProblemArtifactID, path: Self.symbolicPlannerPDDLProblemRelativePath, runID: runID, projectRoot: projectRoot)
        let export = try await persistRunJSON(value, id: Self.symbolicPlannerPDDLExportArtifactID, path: Self.symbolicPlannerPDDLExportRelativePath, runID: runID, projectRoot: projectRoot)
        return XcircuiteSymbolicPlannerPDDLArtifactSet(domainArtifact: domain, problemArtifact: problem, exportArtifact: export)
    }

    public func persistSymbolicPlannerSolverPlan(_ text: String, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try await persistRunText(text, id: Self.symbolicPlannerSolverPlanArtifactID, path: Self.symbolicPlannerSolverPlanRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerPlanReplayValidation(_ value: XcircuiteSymbolicPlannerPlanReplayValidation, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.symbolicPlannerPlanReplayValidationArtifactID, path: Self.symbolicPlannerPlanReplayValidationRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverCertificate(_ value: XcircuiteSymbolicPlannerSolverCertificateParseResult, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.symbolicPlannerSolverCertificateArtifactID, path: Self.symbolicPlannerSolverCertificateRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerProofValidation(_ value: XcircuiteSymbolicPlannerProofValidation, standardOutput: String, standardError: String, runID: String, projectRoot: URL) async throws -> XcircuiteSymbolicPlannerProofValidationArtifactSet {
        try validateRun(value.runID, expected: runID)
        let stdout = try await persistRunText(standardOutput, id: Self.symbolicPlannerProofValidationStdoutArtifactID, path: Self.symbolicPlannerProofValidationStdoutRelativePath, runID: runID, projectRoot: projectRoot)
        let stderr = try await persistRunText(standardError, id: Self.symbolicPlannerProofValidationStderrArtifactID, path: Self.symbolicPlannerProofValidationStderrRelativePath, runID: runID, projectRoot: projectRoot)
        var persisted = value
        persisted.standardOutputArtifact = stdout
        persisted.standardErrorArtifact = stderr
        let validation = try await persistRunJSON(persisted, id: Self.symbolicPlannerProofValidationArtifactID, path: Self.symbolicPlannerProofValidationRelativePath, runID: runID, projectRoot: projectRoot)
        return XcircuiteSymbolicPlannerProofValidationArtifactSet(validationArtifact: validation, standardOutputArtifact: stdout, standardErrorArtifact: stderr)
    }

    public func persistSymbolicPlannerSolverExecution(report: XcircuiteSymbolicPlannerSolverExecutionReport, standardOutput: String, standardError: String, runID: String, projectRoot: URL) async throws -> XcircuiteSymbolicPlannerSolverArtifactSet {
        try validateRun(report.runID, expected: runID)
        let stdout = try await persistRunText(standardOutput, id: Self.symbolicPlannerSolverStdoutArtifactID, path: Self.symbolicPlannerSolverStdoutRelativePath, runID: runID, projectRoot: projectRoot)
        let stderr = try await persistRunText(standardError, id: Self.symbolicPlannerSolverStderrArtifactID, path: Self.symbolicPlannerSolverStderrRelativePath, runID: runID, projectRoot: projectRoot)
        let run = try await persistRunJSON(report, id: Self.symbolicPlannerSolverRunArtifactID, path: Self.symbolicPlannerSolverRunRelativePath, runID: runID, projectRoot: projectRoot)
        return XcircuiteSymbolicPlannerSolverArtifactSet(runArtifact: run, standardOutputArtifact: stdout, standardErrorArtifact: stderr)
    }

    public func persistSymbolicPlannerSolverValidation(_ value: XcircuiteSymbolicPlannerSolverValidationResult, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value.detachingValidationArtifactReferencesForPersistence(), id: Self.symbolicPlannerSolverValidationArtifactID, path: Self.symbolicPlannerSolverValidationRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilyComparison(_ value: XcircuiteSymbolicPlannerSolverFamilyComparison, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        try FlowIdentifierValidator().validate(value.comparisonID, kind: .artifactID)
        let path = "planning/symbolic-planner/solver-family/\(value.comparisonID)/solver-family-comparison.json"
        let id = "\(Self.symbolicPlannerSolverFamilyComparisonArtifactID)-\(String(value.comparisonID.prefix(80)))"
        return try await persistRunJSON(value, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilyPromotion(_ value: XcircuiteSymbolicPlannerSolverFamilyPromotion, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        try FlowIdentifierValidator().validate(value.comparisonID, kind: .artifactID)
        let path = "planning/symbolic-planner/solver-family/\(value.comparisonID)/solver-family-promotion.json"
        let id = "\(Self.symbolicPlannerSolverFamilyPromotionArtifactID)-\(String(value.comparisonID.prefix(80)))"
        return try await persistRunJSON(value, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilyBatch(_ value: XcircuiteSymbolicPlannerSolverFamilyBatchRun, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        try FlowIdentifierValidator().validate(value.comparisonID, kind: .artifactID)
        let path = "planning/symbolic-planner/solver-family/\(value.comparisonID)/solver-family-batch.json"
        let id = "\(Self.symbolicPlannerSolverFamilyBatchArtifactID)-\(String(value.comparisonID.prefix(80)))"
        return try await persistRunJSON(value, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerInstalledSolverLane(_ value: XcircuiteSymbolicPlannerInstalledSolverLane, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        try FlowIdentifierValidator().validate(value.laneID, kind: .artifactID)
        let id = "\(Self.symbolicPlannerInstalledSolverLaneArtifactID)-\(String(value.laneID.prefix(80)))"
        return try await persistRunJSON(value, id: id, path: Self.symbolicPlannerInstalledSolverLaneRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilyValidation(_ value: XcircuiteSymbolicPlannerSolverValidationResult, runID: String, comparisonID: String, candidateID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateFamilyIdentifiers(runID: runID, comparisonID: comparisonID, candidateID: candidateID)
        try validateRun(value.runID, expected: runID)
        let path = familyCandidatePath(comparisonID: comparisonID, candidateID: candidateID, fileName: "solver-validation.json")
        let id = familyArtifactID(Self.symbolicPlannerSolverFamilyValidationArtifactID, comparisonID: comparisonID, candidateID: candidateID)
        return try await persistRunJSON(value.detachingValidationArtifactReferencesForPersistence(), id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilySolverPlan(_ text: String, runID: String, comparisonID: String, candidateID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateFamilyIdentifiers(runID: runID, comparisonID: comparisonID, candidateID: candidateID)
        let path = familyCandidatePath(comparisonID: comparisonID, candidateID: candidateID, fileName: "solver-plan.txt")
        let id = familyArtifactID(Self.symbolicPlannerSolverFamilySolverPlanArtifactID, comparisonID: comparisonID, candidateID: candidateID)
        return try await persistRunText(text, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverFamilyCertificate(_ value: XcircuiteSymbolicPlannerSolverCertificateParseResult, runID: String, comparisonID: String, candidateID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateFamilyIdentifiers(runID: runID, comparisonID: comparisonID, candidateID: candidateID)
        try validateRun(value.runID, expected: runID)
        let path = familyCandidatePath(comparisonID: comparisonID, candidateID: candidateID, fileName: "solver-certificate.json")
        let id = familyArtifactID(Self.symbolicPlannerSolverFamilyCertificateArtifactID, comparisonID: comparisonID, candidateID: candidateID)
        return try await persistRunJSON(value, id: id, path: path, runID: runID, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverCorpusAssessmentSuiteSpec(_ value: XcircuiteSymbolicPlannerSolverCorpusSuiteSpec, projectRoot: URL) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(value.suiteID, kind: .artifactID)
        let path = "\(XcircuiteWorkspaceLayout.directoryName)/assessments/symbolic-planner/\(value.suiteID)/solver-corpus-assessment-suite.json"
        return try await persistProjectJSON(value, id: Self.symbolicPlannerSolverCorpusAssessmentSuiteSpecArtifactID, path: path, projectRoot: projectRoot)
    }

    public func persistSymbolicPlannerSolverCorpusAssessment(_ value: XcircuiteSymbolicPlannerSolverCorpusAssessment, projectRoot: URL) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(value.suiteID, kind: .artifactID)
        let path = "\(XcircuiteWorkspaceLayout.directoryName)/assessments/symbolic-planner/\(value.suiteID)/solver-corpus-assessment.json"
        return try await persistProjectJSON(value, id: Self.symbolicPlannerSolverCorpusAssessmentArtifactID, path: path, projectRoot: projectRoot)
    }

    public func persistPlanVerification(_ value: XcircuitePlanVerification, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistImmutableRunJSON(
            value,
            id: Self.planVerificationArtifactID,
            directory: Self.planVerificationDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func persistPlanExecution(_ value: XcircuiteCandidatePlanExecution, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistImmutableRunJSON(
            value,
            id: Self.planExecutionArtifactID,
            directory: Self.planExecutionDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func persistNumericRepairLoop(_ value: XcircuiteNumericRepairLoopResult, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.numericRepairLoopArtifactID, path: Self.numericRepairLoopRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func persistMetricThresholdProfile(_ value: XcircuiteMetricThresholdProfile, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.metricThresholdProfileArtifactID, path: Self.metricThresholdProfileRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func persistCostCalibrationReport(_ value: XcircuiteCostCalibrationReport, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.costCalibrationArtifactID, path: Self.costCalibrationRelativePath, runID: runID, projectRoot: projectRoot)
    }

    @discardableResult
    public func persistParetoCandidates(_ value: XcircuiteParetoCandidateSet, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunText(try jsonLines(value.candidates), id: Self.paretoCandidatesArtifactID, path: Self.paretoCandidatesRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistImprovementLoop(_ value: XcircuiteImprovementLoopResult, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.improvementLoopArtifactID, path: Self.improvementLoopRelativePath, runID: runID, projectRoot: projectRoot)
    }

    public func persistRejectedFeedbackLearningReport(_ value: XcircuiteRejectedFeedbackLearningReport, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try validateRun(value.runID, expected: runID)
        return try await persistRunJSON(value, id: Self.rejectedFeedbackLearningReportArtifactID, path: Self.rejectedFeedbackLearningReportRelativePath, runID: runID, projectRoot: projectRoot)
    }

    private func persistRunJSON<Value: Encodable & Sendable>(_ value: Value, id: String, path: String, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistRunData(encoder.encode(value), id: id, path: path, format: .json, runID: runID, projectRoot: projectRoot)
    }

    private func persistImmutableRunJSON<Value: Encodable & Sendable>(
        _ value: Value,
        id: String,
        directory: String,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        return try await persistRunData(
            data,
            id: id,
            path: "\(directory)/\(digest.hexadecimalValue).json",
            format: .json,
            runID: runID,
            projectRoot: projectRoot,
            mode: .immutable
        )
    }

    private func persistContentAddressedRunJSON<Value: Encodable & Sendable>(
        _ value: Value,
        identity: String,
        directory: String,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        return try await persistRunData(
            data,
            id: ArtifactID(stableKey: "\(identity):\(digest.hexadecimalValue)").rawValue,
            path: "\(directory)/\(digest.hexadecimalValue).json",
            format: .json,
            runID: runID,
            projectRoot: projectRoot,
            mode: .immutable
        )
    }

    private func persistRunText(_ text: String, id: String, path: String, runID: String, projectRoot: URL) async throws -> ArtifactReference {
        try await persistRunData(Data(text.utf8), id: id, path: path, format: .text, runID: runID, projectRoot: projectRoot)
    }

    private func persistRunData(
        _ data: Data,
        id: String,
        path: String,
        format: ArtifactFormat,
        runID: String,
        projectRoot: URL,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let store = try resolvedWorkspaceStore(projectRoot: projectRoot)
        return try await store.persistArtifact(
            content: data,
            id: try ArtifactID(rawValue: id),
            locator: try artifactLocator(path: runPath(path, runID: runID), format: format),
            runID: runID,
            mode: mode
        )
    }

    private func persistProjectJSON<Value: Encodable & Sendable>(_ value: Value, id: String, path: String, projectRoot: URL) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let store = try resolvedWorkspaceStore(projectRoot: projectRoot)
        return try await store.persistProjectArtifact(
            content: encoder.encode(value),
            id: try ArtifactID(rawValue: id),
            locator: try artifactLocator(path: path, format: .json)
        )
    }

    private func resolvedWorkspaceStore(projectRoot: URL) throws -> XcircuiteWorkspaceStore {
        let canonicalRoot = projectRoot.standardizedFileURL
        guard workspaceStore.projectRoot == canonicalRoot else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(projectRoot.path(percentEncoded: false))
        }
        return workspaceStore
    }

    private func artifactLocator(path: String, format: ArtifactFormat) throws -> ArtifactLocator {
        ArtifactLocator(location: try ArtifactLocation(workspaceRelativePath: path), role: .output, kind: .other, format: format)
    }

    private func runPath(_ path: String, runID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/\(path)"
    }

    private func validateRun(_ actual: String, expected: String) throws {
        try FlowIdentifierValidator().validate(expected, kind: .runID)
        guard actual == expected else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: expected, actual: actual)
        }
    }

    private func validateFamilyIdentifiers(runID: String, comparisonID: String, candidateID: String) throws {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        try FlowIdentifierValidator().validate(comparisonID, kind: .artifactID)
        try FlowIdentifierValidator().validate(candidateID, kind: .artifactID)
    }

    private func familyCandidatePath(comparisonID: String, candidateID: String, fileName: String) -> String {
        "planning/symbolic-planner/solver-family/\(comparisonID)/candidates/\(candidateID)/\(fileName)"
    }

    private func familyArtifactID(_ prefix: String, comparisonID: String, candidateID: String) -> String {
        "\(prefix)-\(String(comparisonID.prefix(48)))-\(String(candidateID.prefix(48)))"
    }

    private func jsonLines<Value: Encodable>(_ values: [Value]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        for value in values {
            let data = try encoder.encode(value)
            guard let line = String(data: data, encoding: .utf8) else {
                throw XcircuitePlanningArtifactError.invalidUTF8
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func decodeRejectedPlans(_ data: Data, runID: String) throws -> [XcircuiteRejectedPlanRecord] {
        var records: [XcircuiteRejectedPlanRecord] = []
        var identifiers: Set<String> = []
        for (index, line) in data.split(separator: 0x0A).enumerated() {
            do {
                let record = try JSONDecoder().decode(XcircuiteRejectedPlanRecord.self, from: Data(line))
                try validateRun(record.runID, expected: runID)
                guard identifiers.insert(record.rejectionID).inserted else {
                    throw XcircuitePlanningArtifactError.duplicateRejectedPlan(rejectionID: record.rejectionID)
                }
                records.append(record)
            } catch {
                throw XcircuitePlanningArtifactError.invalidJSONLLine(
                    path: runPath(Self.rejectedPlansRelativePath, runID: runID),
                    line: index + 1,
                    message: error.localizedDescription
                )
            }
        }
        return records
    }

    private static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
