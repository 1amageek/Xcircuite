import Foundation
import DesignFlowKernel

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
    public static let symbolicPlannerTraceArtifactID = "planning-symbolic-planner-trace"
    public static let symbolicPlannerTraceRelativePath = "planning/symbolic-planner-trace.json"
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
    public static let symbolicPlannerSolverQualificationArtifactID = "planning-symbolic-planner-solver-qualification"
    public static let symbolicPlannerSolverQualificationRelativePath = "planning/symbolic-planner/solver-qualification.json"
    public static let symbolicPlannerSolverFamilyComparisonArtifactID = "planning-symbolic-planner-solver-family-comparison"
    public static let symbolicPlannerSolverFamilyComparisonRelativePath = "planning/symbolic-planner/solver-family/solver-family-comparison.json"
    public static let symbolicPlannerSolverFamilyPromotionArtifactID = "planning-symbolic-planner-solver-family-promotion"
    public static let symbolicPlannerSolverFamilyPromotionRelativePath = "planning/symbolic-planner/solver-family/solver-family-promotion.json"
    public static let symbolicPlannerSolverFamilyBatchArtifactID = "planning-symbolic-planner-solver-family-batch"
    public static let symbolicPlannerSolverFamilyBatchRelativePath = "planning/symbolic-planner/solver-family/solver-family-batch.json"
    public static let symbolicPlannerSolverFamilyQualificationArtifactID = "planning-symbolic-planner-solver-family-qualification"
    public static let symbolicPlannerSolverFamilySolverPlanArtifactID = "planning-symbolic-planner-solver-family-solver-plan"
    public static let symbolicPlannerSolverFamilyCertificateArtifactID = "planning-symbolic-planner-solver-family-certificate"
    public static let symbolicPlannerInstalledSolverLaneArtifactID = "planning-symbolic-planner-installed-solver-lane"
    public static let symbolicPlannerInstalledSolverLaneRelativePath = "planning/symbolic-planner/installed-solver-lane.json"
    public static let symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID = "planning-symbolic-planner-solver-qualification-corpus-suite-spec"
    public static let symbolicPlannerSolverQualificationCorpusArtifactID = "planning-symbolic-planner-solver-qualification-corpus"
    public static let parameterCandidatesArtifactID = "planning-parameter-candidates"
    public static let parameterCandidatesRelativePath = "planning/parameter-candidates.jsonl"
    public static let parameterCandidateSearchTraceArtifactID = "planning-parameter-candidate-search-trace"
    public static let parameterCandidateSearchTraceRelativePath = "planning/parameter-candidate-search-trace.json"
    public static let parameterCandidateSelectionTraceArtifactID = "planning-parameter-candidate-selection-trace"
    public static let parameterCandidateSelectionTraceRelativePath = "planning/parameter-candidate-selection-trace.json"
    public static let rejectedPlansArtifactID = "planning-rejected-plans"
    public static let rejectedPlansRelativePath = "planning/rejected-plans.jsonl"
    public static let planVerificationArtifactID = "planning-plan-verification"
    public static let planVerificationRelativePath = "planning/plan-verification.json"
    public static let planExecutionArtifactID = "planning-plan-execution"
    public static let planExecutionRelativePath = "planning/plan-execution.json"
    public static let candidateCycleHistorySummaryArtifactID = "planning-candidate-cycle-history-summary"
    public static let candidateCycleHistorySummaryRelativePath = "planning/candidate-cycle-history-summary.json"
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

    private let packageStore: XcircuitePackageStore
    private let snapshotBuilder: XcircuiteActionDomainSnapshotBuilder

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        snapshotBuilder: XcircuiteActionDomainSnapshotBuilder = XcircuiteActionDomainSnapshotBuilder()
    ) {
        self.packageStore = packageStore
        self.snapshotBuilder = snapshotBuilder
    }

    @discardableResult
    public func persistActionDomainSnapshot(
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try persistActionDomainSnapshot(
            runID: runID,
            projectRoot: projectRoot,
            generatedAt: Self.currentTimestamp()
        )
    }

    @discardableResult
    public func persistActionDomainSnapshot(
        runID: String,
        projectRoot: URL,
        generatedAt: String
    ) throws -> XcircuiteFileReference {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let snapshot = try snapshotBuilder.snapshot(runID: runID, generatedAt: generatedAt)
        let snapshotURL = planningDirectory.appending(path: "action-domain-snapshot.json")
        try packageStore.writeJSON(snapshot, to: snapshotURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.actionDomainRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.actionDomainArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistRepairPlanFormulation(
        _ formulation: XcircuiteRepairPlanFormulation,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard formulation.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: formulation.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let formulationURL = planningDirectory.appending(path: "repair-formulation.json")
        try packageStore.writeJSON(formulation, to: formulationURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.repairPlanFormulationRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.repairPlanFormulationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistPlanningProblem(
        _ problem: XcircuiteCircuitPlanningProblem,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard problem.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: problem.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let problemURL = planningDirectory.appending(path: "problem.json")
        try packageStore.writeJSON(problem, to: problemURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.problemRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.problemArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistPlanningProblemValidation(
        _ validation: XcircuitePlanningProblemValidation,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard validation.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: validation.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let validationURL = planningDirectory.appending(path: "problem-validation.json")
        try packageStore.writeJSON(validation, to: validationURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.planningProblemValidationRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.planningProblemValidationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistProblemTranslationAudit(
        _ audit: XcircuiteProblemTranslationAudit,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard audit.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: audit.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let auditURL = planningDirectory.appending(path: "problem-translation-audit.json")
        try packageStore.writeJSON(audit, to: auditURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.problemTranslationAuditRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.problemTranslationAuditArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistParameterCandidates(
        _ candidates: [XcircuiteParameterCandidate],
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        if let mismatched = candidates.first(where: { $0.runID != runID }) {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: mismatched.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let candidatesURL = planningDirectory.appending(path: "parameter-candidates.jsonl")
        try packageStore.writeText(try jsonLines(for: candidates), to: candidatesURL)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.parameterCandidatesRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.parameterCandidatesArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func appendRejectedPlan(
        _ record: XcircuiteRejectedPlanRecord,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard record.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: record.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let rejectedPlansURL = planningDirectory.appending(path: "rejected-plans.jsonl")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard let line = String(data: data, encoding: .utf8) else {
            throw XcircuitePlanningArtifactError.invalidUTF8
        }
        let existingRecords = try readRejectedPlanLedger(from: rejectedPlansURL, runID: runID)
        if existingRecords.contains(where: { $0.rejectionID == record.rejectionID }) {
            throw XcircuitePlanningArtifactError.duplicateRejectedPlan(rejectionID: record.rejectionID)
        }
        let existingText = try rejectedPlanLedgerText(from: rejectedPlansURL)
        let prefix = existingText.isEmpty || existingText.hasSuffix("\n") ? existingText : "\(existingText)\n"
        try packageStore.writeText("\(prefix)\(line)\n", to: rejectedPlansURL)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.rejectedPlansRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.rejectedPlansArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistParameterCandidateSearchTrace(
        _ trace: XcircuiteParameterCandidateSearchTrace,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard trace.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: trace.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let traceURL = planningDirectory.appending(path: "parameter-candidate-search-trace.json")
        try packageStore.writeJSON(trace, to: traceURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.parameterCandidateSearchTraceRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.parameterCandidateSearchTraceArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistParameterCandidateSelectionTrace(
        _ trace: XcircuiteParameterCandidateSelectionTrace,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let traceURL = planningDirectory.appending(path: "parameter-candidate-selection-trace.json")
        try packageStore.writeJSON(trace, to: traceURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.parameterCandidateSelectionTraceRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.parameterCandidateSelectionTraceArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistCandidatePlan(
        _ plan: XcircuiteCandidatePlan,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard plan.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: plan.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let candidatePlanURL = planningDirectory.appending(path: "candidate-plan.json")
        try packageStore.writeJSON(plan, to: candidatePlanURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.candidatePlanRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.candidatePlanArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerTrace(
        _ trace: XcircuiteSymbolicPlannerTrace,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard trace.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: trace.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let traceURL = planningDirectory.appending(path: "symbolic-planner-trace.json")
        try packageStore.writeJSON(trace, to: traceURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerTraceRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.symbolicPlannerTraceArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerFamilyRun(
        _ familyRun: XcircuiteSymbolicPlannerFamilyRun,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(familyRun.familyRunID, kind: .artifactID)
        guard familyRun.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: familyRun.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let familyDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "family")
            .appending(path: familyRun.familyRunID)
        try packageStore.ensureDirectory(at: familyDirectory)

        let familyRunURL = familyDirectory.appending(path: "family-run.json")
        try packageStore.writeJSON(familyRun, to: familyRunURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/family/\(familyRun.familyRunID)/family-run.json"
        let familyArtifactID = "\(Self.symbolicPlannerFamilyRunArtifactID)-\(String(familyRun.familyRunID.prefix(80)))"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: familyArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerPDDLExport(
        _ export: XcircuiteSymbolicPlannerPDDLExport,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerPDDLArtifactSet {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard export.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: export.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let domainURL = exportDirectory.appending(path: "domain.pddl")
        let problemURL = exportDirectory.appending(path: "problem.pddl")
        let exportURL = exportDirectory.appending(path: "pddl-export.json")
        try packageStore.writeText(export.domainPDDL, to: domainURL)
        try packageStore.writeText(export.problemPDDL, to: problemURL)
        try packageStore.writeJSON(export, to: exportURL, forProjectAt: projectRoot)

        let domainArtifact = try pddlFileReference(
            relativePath: Self.symbolicPlannerPDDLDomainRelativePath,
            artifactID: Self.symbolicPlannerPDDLDomainArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        let problemArtifact = try pddlFileReference(
            relativePath: Self.symbolicPlannerPDDLProblemRelativePath,
            artifactID: Self.symbolicPlannerPDDLProblemArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        let exportArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerPDDLExportRelativePath)",
            artifactID: Self.symbolicPlannerPDDLExportArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )

        try packageStore.upsertRunArtifact(domainArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(problemArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(exportArtifact, runID: runID, inProjectAt: projectRoot)

        return XcircuiteSymbolicPlannerPDDLArtifactSet(
            domainArtifact: domainArtifact,
            problemArtifact: problemArtifact,
            exportArtifact: exportArtifact
        )
    }

    @discardableResult
    public func persistSymbolicPlannerSolverPlan(
        _ text: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let planURL = exportDirectory.appending(path: "solver-plan.txt")
        try packageStore.writeText(text, to: planURL)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverPlanRelativePath)",
            artifactID: Self.symbolicPlannerSolverPlanArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerPlanReplayValidation(
        _ validation: XcircuiteSymbolicPlannerPlanReplayValidation,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard validation.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: validation.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let validationURL = exportDirectory.appending(path: "plan-replay-validation.json")
        try packageStore.writeJSON(validation, to: validationURL, forProjectAt: projectRoot)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerPlanReplayValidationRelativePath)",
            artifactID: Self.symbolicPlannerPlanReplayValidationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverCertificate(
        _ certificate: XcircuiteSymbolicPlannerSolverCertificateParseResult,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard certificate.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: certificate.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let certificateURL = exportDirectory.appending(path: "solver-certificate.json")
        try packageStore.writeJSON(certificate, to: certificateURL, forProjectAt: projectRoot)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverCertificateRelativePath)",
            artifactID: Self.symbolicPlannerSolverCertificateArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerProofValidation(
        _ validation: XcircuiteSymbolicPlannerProofValidation,
        standardOutput: String,
        standardError: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerProofValidationArtifactSet {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard validation.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: validation.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let stdoutURL = exportDirectory.appending(path: "proof-validation-stdout.txt")
        let stderrURL = exportDirectory.appending(path: "proof-validation-stderr.txt")
        let validationURL = exportDirectory.appending(path: "proof-validation.json")
        try packageStore.writeText(standardOutput, to: stdoutURL)
        try packageStore.writeText(standardError, to: stderrURL)

        let stdoutArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerProofValidationStdoutRelativePath)",
            artifactID: Self.symbolicPlannerProofValidationStdoutArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        let stderrArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerProofValidationStderrRelativePath)",
            artifactID: Self.symbolicPlannerProofValidationStderrArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        var persistedValidation = validation
        persistedValidation.standardOutputArtifact = stdoutArtifact
        persistedValidation.standardErrorArtifact = stderrArtifact
        try packageStore.writeJSON(persistedValidation, to: validationURL, forProjectAt: projectRoot)

        let validationArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerProofValidationRelativePath)",
            artifactID: Self.symbolicPlannerProofValidationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )

        try packageStore.upsertRunArtifact(stdoutArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(stderrArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(validationArtifact, runID: runID, inProjectAt: projectRoot)
        return XcircuiteSymbolicPlannerProofValidationArtifactSet(
            validationArtifact: validationArtifact,
            standardOutputArtifact: stdoutArtifact,
            standardErrorArtifact: stderrArtifact
        )
    }

    @discardableResult
    public func persistSymbolicPlannerSolverExecution(
        report: XcircuiteSymbolicPlannerSolverExecutionReport,
        standardOutput: String,
        standardError: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerSolverArtifactSet {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard report.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: report.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let stdoutURL = exportDirectory.appending(path: "solver-stdout.txt")
        let stderrURL = exportDirectory.appending(path: "solver-stderr.txt")
        let reportURL = exportDirectory.appending(path: "solver-run.json")
        try packageStore.writeText(standardOutput, to: stdoutURL)
        try packageStore.writeText(standardError, to: stderrURL)
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)

        let stdoutArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverStdoutRelativePath)",
            artifactID: Self.symbolicPlannerSolverStdoutArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        let stderrArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverStderrRelativePath)",
            artifactID: Self.symbolicPlannerSolverStderrArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        let runArtifact = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverRunRelativePath)",
            artifactID: Self.symbolicPlannerSolverRunArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )

        try packageStore.upsertRunArtifact(stdoutArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(stderrArtifact, runID: runID, inProjectAt: projectRoot)
        try packageStore.upsertRunArtifact(runArtifact, runID: runID, inProjectAt: projectRoot)
        return XcircuiteSymbolicPlannerSolverArtifactSet(
            runArtifact: runArtifact,
            standardOutputArtifact: stdoutArtifact,
            standardErrorArtifact: stderrArtifact
        )
    }

    @discardableResult
    public func persistSymbolicPlannerSolverQualification(
        _ qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard qualification.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: qualification.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "solver-qualification.json")
        let persistedQualification = qualification.detachingQualificationArtifactReferencesForPersistence()
        try packageStore.writeJSON(persistedQualification, to: reportURL, forProjectAt: projectRoot)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.symbolicPlannerSolverQualificationRelativePath)",
            artifactID: Self.symbolicPlannerSolverQualificationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilyComparison(
        _ comparison: XcircuiteSymbolicPlannerSolverFamilyComparison,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(comparison.comparisonID, kind: .artifactID)
        guard comparison.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: comparison.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: comparison.comparisonID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "solver-family-comparison.json")
        try packageStore.writeJSON(comparison, to: reportURL, forProjectAt: projectRoot)

        let comparisonArtifactID = "\(Self.symbolicPlannerSolverFamilyComparisonArtifactID)-\(String(comparison.comparisonID.prefix(80)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparison.comparisonID)/solver-family-comparison.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: comparisonArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilyPromotion(
        _ promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(promotion.comparisonID, kind: .artifactID)
        guard promotion.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: promotion.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: promotion.comparisonID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "solver-family-promotion.json")
        try packageStore.writeJSON(promotion, to: reportURL, forProjectAt: projectRoot)

        let promotionArtifactID = "\(Self.symbolicPlannerSolverFamilyPromotionArtifactID)-\(String(promotion.comparisonID.prefix(80)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(promotion.comparisonID)/solver-family-promotion.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: promotionArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilyBatch(
        _ batchRun: XcircuiteSymbolicPlannerSolverFamilyBatchRun,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(batchRun.comparisonID, kind: .artifactID)
        guard batchRun.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: batchRun.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: batchRun.comparisonID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "solver-family-batch.json")
        try packageStore.writeJSON(batchRun, to: reportURL, forProjectAt: projectRoot)

        let batchArtifactID = "\(Self.symbolicPlannerSolverFamilyBatchArtifactID)-\(String(batchRun.comparisonID.prefix(80)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(batchRun.comparisonID)/solver-family-batch.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: batchArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerInstalledSolverLane(
        _ lane: XcircuiteSymbolicPlannerInstalledSolverLane,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(lane.laneID, kind: .artifactID)
        guard lane.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: lane.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "installed-solver-lane.json")
        try packageStore.writeJSON(lane, to: reportURL, forProjectAt: projectRoot)

        let artifactID = "\(Self.symbolicPlannerInstalledSolverLaneArtifactID)-\(String(lane.laneID.prefix(80)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/installed-solver-lane.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilyQualification(
        _ qualification: XcircuiteSymbolicPlannerSolverQualificationResult,
        runID: String,
        comparisonID: String,
        candidateID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(comparisonID, kind: .artifactID)
        try XcircuiteIdentifierValidator().validate(candidateID, kind: .artifactID)
        guard qualification.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: qualification.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: comparisonID)
            .appending(path: "candidates")
            .appending(path: candidateID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let reportURL = exportDirectory.appending(path: "solver-qualification.json")
        let persistedQualification = qualification.detachingQualificationArtifactReferencesForPersistence()
        try packageStore.writeJSON(persistedQualification, to: reportURL, forProjectAt: projectRoot)

        let artifactID = "\(Self.symbolicPlannerSolverFamilyQualificationArtifactID)-\(String(comparisonID.prefix(48)))-\(String(candidateID.prefix(48)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)/candidates/\(candidateID)/solver-qualification.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilySolverPlan(
        _ solverPlanText: String,
        runID: String,
        comparisonID: String,
        candidateID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(comparisonID, kind: .artifactID)
        try XcircuiteIdentifierValidator().validate(candidateID, kind: .artifactID)
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: comparisonID)
            .appending(path: "candidates")
            .appending(path: candidateID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let solverPlanURL = exportDirectory.appending(path: "solver-plan.txt")
        try packageStore.writeText(solverPlanText, to: solverPlanURL)

        let artifactID = "\(Self.symbolicPlannerSolverFamilySolverPlanArtifactID)-\(String(comparisonID.prefix(48)))-\(String(candidateID.prefix(48)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)/candidates/\(candidateID)/solver-plan.txt"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverFamilyCertificate(
        _ certificate: XcircuiteSymbolicPlannerSolverCertificateParseResult,
        runID: String,
        comparisonID: String,
        candidateID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(comparisonID, kind: .artifactID)
        try XcircuiteIdentifierValidator().validate(candidateID, kind: .artifactID)
        guard certificate.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: certificate.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let exportDirectory = runDirectory
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "solver-family")
            .appending(path: comparisonID)
            .appending(path: "candidates")
            .appending(path: candidateID)
        try packageStore.ensureDirectory(at: exportDirectory)

        let certificateURL = exportDirectory.appending(path: "solver-certificate.json")
        try packageStore.writeJSON(certificate, to: certificateURL, forProjectAt: projectRoot)

        let artifactID = "\(Self.symbolicPlannerSolverFamilyCertificateArtifactID)-\(String(comparisonID.prefix(48)))-\(String(candidateID.prefix(48)))"
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)/candidates/\(candidateID)/solver-certificate.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverQualificationCorpusSuiteSpec(
        _ suiteSpec: XcircuiteSymbolicPlannerSolverCorpusSuiteSpec,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(suiteSpec.suiteID, kind: .artifactID)
        let suiteDirectory = XcircuitePackage(projectRoot: projectRoot)
            .packageURL
            .appending(path: "qualification")
            .appending(path: "symbolic-planner")
            .appending(path: suiteSpec.suiteID)
        try packageStore.ensureDirectory(at: suiteDirectory)

        let suiteSpecURL = suiteDirectory.appending(path: "solver-qualification-corpus-suite.json")
        try packageStore.writeJSON(suiteSpec, to: suiteSpecURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/qualification/symbolic-planner/\(suiteSpec.suiteID)/solver-qualification-corpus-suite.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(reference, forProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistSymbolicPlannerSolverQualificationCorpus(
        _ corpus: XcircuiteSymbolicPlannerSolverCorpusQualificationResult,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(corpus.suiteID, kind: .artifactID)
        let corpusDirectory = XcircuitePackage(projectRoot: projectRoot)
            .packageURL
            .appending(path: "qualification")
            .appending(path: "symbolic-planner")
            .appending(path: corpus.suiteID)
        try packageStore.ensureDirectory(at: corpusDirectory)

        let corpusURL = corpusDirectory.appending(path: "solver-qualification-corpus.json")
        try packageStore.writeJSON(corpus, to: corpusURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/qualification/symbolic-planner/\(corpus.suiteID)/solver-qualification-corpus.json"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.symbolicPlannerSolverQualificationCorpusArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(reference, forProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistPlanVerification(
        _ verification: XcircuitePlanVerification,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard verification.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: verification.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let verificationURL = planningDirectory.appending(path: "plan-verification.json")
        try packageStore.writeJSON(verification, to: verificationURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.planVerificationRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.planVerificationArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistPlanExecution(
        _ execution: XcircuiteCandidatePlanExecution,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard execution.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: execution.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let executionURL = planningDirectory.appending(path: "plan-execution.json")
        try packageStore.writeJSON(execution, to: executionURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.planExecutionRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.planExecutionArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistNumericRepairLoop(
        _ loop: XcircuiteNumericRepairLoopResult,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard loop.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: loop.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let loopURL = planningDirectory.appending(path: "numeric-repair-loop.json")
        try packageStore.writeJSON(loop, to: loopURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.numericRepairLoopRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.numericRepairLoopArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistMetricThresholdProfile(
        _ profile: XcircuiteMetricThresholdProfile,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard profile.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: profile.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let profileURL = planningDirectory.appending(path: "metric-threshold-profile.json")
        try packageStore.writeJSON(profile, to: profileURL, forProjectAt: projectRoot)

        let reference = try jsonPlanningFileReference(
            relativePath: Self.metricThresholdProfileRelativePath,
            artifactID: Self.metricThresholdProfileArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistCostCalibrationReport(
        _ report: XcircuiteCostCalibrationReport,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard report.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: report.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let reportURL = planningDirectory.appending(path: "cost-calibration.json")
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)

        let reference = try jsonPlanningFileReference(
            relativePath: Self.costCalibrationRelativePath,
            artifactID: Self.costCalibrationArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistParetoCandidates(
        _ candidateSet: XcircuiteParetoCandidateSet,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard candidateSet.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: candidateSet.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let candidatesURL = planningDirectory.appending(path: "pareto-candidates.jsonl")
        try packageStore.writeText(try jsonLines(for: candidateSet.candidates), to: candidatesURL)

        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.paretoCandidatesRelativePath)",
            artifactID: Self.paretoCandidatesArtifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistImprovementLoop(
        _ loop: XcircuiteImprovementLoopResult,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard loop.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: loop.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let loopURL = planningDirectory.appending(path: "improvement-loop.json")
        try packageStore.writeJSON(loop, to: loopURL, forProjectAt: projectRoot)

        let reference = try jsonPlanningFileReference(
            relativePath: Self.improvementLoopRelativePath,
            artifactID: Self.improvementLoopArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func persistRejectedFeedbackLearningReport(
        _ report: XcircuiteRejectedFeedbackLearningReport,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        guard report.runID == runID else {
            throw XcircuitePlanningArtifactError.runMismatch(expected: runID, actual: report.runID)
        }
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try packageStore.ensureDirectory(at: planningDirectory)

        let reportURL = planningDirectory.appending(path: "rejected-feedback-learning-report.json")
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)

        let reference = try jsonPlanningFileReference(
            relativePath: Self.rejectedFeedbackLearningReportRelativePath,
            artifactID: Self.rejectedFeedbackLearningReportArtifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    private static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func jsonLines<T: Encodable>(for values: [T]) throws -> String {
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

    private func rejectedPlanLedgerText(from url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func readRejectedPlanLedger(
        from url: URL,
        runID: String
    ) throws -> [XcircuiteRejectedPlanRecord] {
        let text = try rejectedPlanLedgerText(from: url)
        guard !text.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        let path = url.path(percentEncoded: false)
        var records: [XcircuiteRejectedPlanRecord] = []
        var seenRejectionIDs: Set<String> = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let lineText = String(line)
            guard !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let record: XcircuiteRejectedPlanRecord
            do {
                record = try decoder.decode(XcircuiteRejectedPlanRecord.self, from: Data(lineText.utf8))
            } catch {
                throw XcircuitePlanningArtifactError.invalidJSONLLine(
                    path: path,
                    line: lineNumber,
                    message: error.localizedDescription
                )
            }
            guard record.runID == runID else {
                throw XcircuitePlanningArtifactError.invalidJSONLLine(
                    path: path,
                    line: lineNumber,
                    message: XcircuitePlanningArtifactError.runMismatch(
                        expected: runID,
                        actual: record.runID
                    ).localizedDescription
                )
            }
            guard seenRejectionIDs.insert(record.rejectionID).inserted else {
                throw XcircuitePlanningArtifactError.invalidJSONLLine(
                    path: path,
                    line: lineNumber,
                    message: XcircuitePlanningArtifactError.duplicateRejectedPlan(
                        rejectionID: record.rejectionID
                    ).localizedDescription
                )
            }
            records.append(record)
        }
        return records
    }

    private func pddlFileReference(
        relativePath: String,
        artifactID: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)",
            artifactID: artifactID,
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }

    private func jsonPlanningFileReference(
        relativePath: String,
        artifactID: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)",
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }
}
