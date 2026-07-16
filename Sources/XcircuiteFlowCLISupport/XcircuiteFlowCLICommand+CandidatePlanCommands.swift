import Foundation
import Xcircuite
import DesignFlowKernel

extension XcircuiteFlowCLICommand {
    static func synthesizeParameterCandidatePlan(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var parameterCandidatesArtifactID: String?
        var parameterCandidatesPath: String?
        var rejectedPlansArtifactID: String?
        var rejectedPlansPath: String?
        var candidateID: String?
        var rank: Int?
        var strategy = "parameter-candidate-to-netlist-edit"
        var includeRejectedCandidates = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--parameter-candidates-artifact-id":
                parameterCandidatesArtifactID = try parser.requiredValue(after: argument)
            case "--parameter-candidates-path":
                parameterCandidatesPath = try parser.requiredValue(after: argument)
            case "--rejected-plans-artifact-id":
                rejectedPlansArtifactID = try parser.requiredValue(after: argument)
            case "--rejected-plans-path":
                rejectedPlansPath = try parser.requiredValue(after: argument)
            case "--candidate-id":
                candidateID = try parser.requiredValue(after: argument)
            case "--rank":
                rank = try parser.requiredInt(after: argument)
            case "--strategy":
                strategy = try parser.requiredValue(after: argument)
            case "--include-rejected-candidates":
                includeRejectedCandidates = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return synthesizeParameterCandidatePlanHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteParameterCandidatePlanSynthesizer(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                parameterCandidatesArtifactID: parameterCandidatesArtifactID,
                parameterCandidatesPath: parameterCandidatesPath,
                rejectedPlansArtifactID: rejectedPlansArtifactID,
                rejectedPlansPath: rejectedPlansPath,
                candidateID: candidateID,
                rank: rank,
                strategy: strategy,
                includeRejectedCandidates: includeRejectedCandidates
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func generateParameterCandidates(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var rejectedPlansArtifactID: String?
        var rejectedPlansPath: String?
        var previousParameterCandidatesArtifactID: String?
        var previousParameterCandidatesPath: String?
        var metricThresholdProfileArtifactID: String?
        var metricThresholdProfilePath: String?
        var costCalibrationArtifactID: String?
        var costCalibrationPath: String?
        var paretoCandidatesArtifactID: String?
        var paretoCandidatesPath: String?
        var strategy = "bounded-midpoint-sweep"
        var maxCandidates = 9
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--rejected-plans-artifact-id":
                rejectedPlansArtifactID = try parser.requiredValue(after: argument)
            case "--rejected-plans-path":
                rejectedPlansPath = try parser.requiredValue(after: argument)
            case "--previous-parameter-candidates-artifact-id":
                previousParameterCandidatesArtifactID = try parser.requiredValue(after: argument)
            case "--previous-parameter-candidates-path":
                previousParameterCandidatesPath = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-artifact-id":
                metricThresholdProfileArtifactID = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-path":
                metricThresholdProfilePath = try parser.requiredValue(after: argument)
            case "--cost-calibration-artifact-id":
                costCalibrationArtifactID = try parser.requiredValue(after: argument)
            case "--cost-calibration-path":
                costCalibrationPath = try parser.requiredValue(after: argument)
            case "--pareto-candidates-artifact-id":
                paretoCandidatesArtifactID = try parser.requiredValue(after: argument)
            case "--pareto-candidates-path":
                paretoCandidatesPath = try parser.requiredValue(after: argument)
            case "--strategy":
                strategy = try parser.requiredValue(after: argument)
            case "--max-candidates":
                maxCandidates = try parser.requiredInt(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return generateParameterCandidatesHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteParameterCandidateGenerator(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                rejectedPlansArtifactID: rejectedPlansArtifactID,
                rejectedPlansPath: rejectedPlansPath,
                previousParameterCandidatesArtifactID: previousParameterCandidatesArtifactID,
                previousParameterCandidatesPath: previousParameterCandidatesPath,
                metricThresholdProfileArtifactID: metricThresholdProfileArtifactID,
                metricThresholdProfilePath: metricThresholdProfilePath,
                costCalibrationArtifactID: costCalibrationArtifactID,
                costCalibrationPath: costCalibrationPath,
                paretoCandidatesArtifactID: paretoCandidatesArtifactID,
                paretoCandidatesPath: paretoCandidatesPath,
                strategy: strategy,
                maxCandidates: maxCandidates
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func generateCandidatePlan(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var rejectedPlansArtifactID: String?
        var rejectedPlansPath: String?
        var metricThresholdProfileArtifactID: String?
        var metricThresholdProfilePath: String?
        var costCalibrationArtifactID: String?
        var costCalibrationPath: String?
        var paretoCandidatesArtifactID: String?
        var paretoCandidatesPath: String?
        var strategy = "first-ready-action-per-objective"
        var calibrationPolicy = "disabled"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--rejected-plans-artifact-id":
                rejectedPlansArtifactID = try parser.requiredValue(after: argument)
            case "--rejected-plans-path":
                rejectedPlansPath = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-artifact-id":
                metricThresholdProfileArtifactID = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-path":
                metricThresholdProfilePath = try parser.requiredValue(after: argument)
            case "--cost-calibration-artifact-id":
                costCalibrationArtifactID = try parser.requiredValue(after: argument)
            case "--cost-calibration-path":
                costCalibrationPath = try parser.requiredValue(after: argument)
            case "--pareto-candidates-artifact-id":
                paretoCandidatesArtifactID = try parser.requiredValue(after: argument)
            case "--pareto-candidates-path":
                paretoCandidatesPath = try parser.requiredValue(after: argument)
            case "--strategy":
                strategy = try parser.requiredValue(after: argument)
            case "--calibration-policy":
                calibrationPolicy = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return generateCandidatePlanHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                rejectedPlansArtifactID: rejectedPlansArtifactID,
                rejectedPlansPath: rejectedPlansPath,
                metricThresholdProfileArtifactID: metricThresholdProfileArtifactID,
                metricThresholdProfilePath: metricThresholdProfilePath,
                costCalibrationArtifactID: costCalibrationArtifactID,
                costCalibrationPath: costCalibrationPath,
                paretoCandidatesArtifactID: paretoCandidatesArtifactID,
                paretoCandidatesPath: paretoCandidatesPath,
                strategy: strategy,
                calibrationPolicy: calibrationPolicy
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func runSymbolicPlannerFamily(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var familyRunID = "family-run-1"
        var problemArtifactID: String?
        var problemPath: String?
        var rejectedPlansArtifactID: String?
        var rejectedPlansPath: String?
        var metricThresholdProfileArtifactID: String?
        var metricThresholdProfilePath: String?
        var costCalibrationArtifactID: String?
        var costCalibrationPath: String?
        var paretoCandidatesArtifactID: String?
        var paretoCandidatesPath: String?
        var strategies: [String] = []
        var calibrationPolicy = "disabled"
        var selectionPolicy = "prefer-ready-then-goal-coverage-then-score"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--family-run-id":
                familyRunID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--rejected-plans-artifact-id":
                rejectedPlansArtifactID = try parser.requiredValue(after: argument)
            case "--rejected-plans-path":
                rejectedPlansPath = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-artifact-id":
                metricThresholdProfileArtifactID = try parser.requiredValue(after: argument)
            case "--metric-threshold-profile-path":
                metricThresholdProfilePath = try parser.requiredValue(after: argument)
            case "--cost-calibration-artifact-id":
                costCalibrationArtifactID = try parser.requiredValue(after: argument)
            case "--cost-calibration-path":
                costCalibrationPath = try parser.requiredValue(after: argument)
            case "--pareto-candidates-artifact-id":
                paretoCandidatesArtifactID = try parser.requiredValue(after: argument)
            case "--pareto-candidates-path":
                paretoCandidatesPath = try parser.requiredValue(after: argument)
            case "--strategy":
                strategies.append(try parser.requiredValue(after: argument))
            case "--calibration-policy":
                calibrationPolicy = try parser.requiredValue(after: argument)
            case "--selection-policy":
                selectionPolicy = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return runSymbolicPlannerFamilyHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }
        let requestedStrategies = strategies.isEmpty
            ? XcircuiteSymbolicPlannerFamilyRunRequest(runID: runID).strategies
            : strategies
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).runSymbolicPlannerFamily(
            request: XcircuiteSymbolicPlannerFamilyRunRequest(
                runID: runID,
                familyRunID: familyRunID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                rejectedPlansArtifactID: rejectedPlansArtifactID,
                rejectedPlansPath: rejectedPlansPath,
                metricThresholdProfileArtifactID: metricThresholdProfileArtifactID,
                metricThresholdProfilePath: metricThresholdProfilePath,
                costCalibrationArtifactID: costCalibrationArtifactID,
                costCalibrationPath: costCalibrationPath,
                paretoCandidatesArtifactID: paretoCandidatesArtifactID,
                paretoCandidatesPath: paretoCandidatesPath,
                strategies: requestedStrategies,
                calibrationPolicy: calibrationPolicy,
                selectionPolicy: selectionPolicy
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func verifyCandidatePlan(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var candidatePlanArtifactID: String?
        var candidatePlanPath: String?
        var verificationMode = "preflight"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--candidate-plan-artifact-id":
                candidatePlanArtifactID = try parser.requiredValue(after: argument)
            case "--candidate-plan-path":
                candidatePlanPath = try parser.requiredValue(after: argument)
            case "--mode":
                verificationMode = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return verifyCandidatePlanHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                candidatePlanArtifactID: candidatePlanArtifactID,
                candidatePlanPath: candidatePlanPath,
                verificationMode: verificationMode
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func approveCandidatePlanRisk(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var approvalID: String?
        var reviewer: String?
        var reviewerKind = FlowRunActor.Kind.human
        var verdict = FlowApprovalRecord.Verdict.approved
        var note = ""
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--approval-id":
                approvalID = try parser.requiredValue(after: argument)
            case "--reviewer":
                reviewer = try parser.requiredValue(after: argument)
            case "--reviewer-kind":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = FlowRunActor.Kind(rawValue: value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                reviewerKind = parsed
            case "--decision":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = FlowApprovalRecord.Verdict(rawValue: value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                verdict = parsed
            case "--note":
                note = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return approveCandidatePlanRiskHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }
        guard let approvalID else {
            throw XcircuiteFlowCLIError.missingOption("--approval-id")
        }
        guard let reviewer else {
            throw XcircuiteFlowCLIError.missingOption("--reviewer")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteCandidatePlanRiskApprovalRecorder(
            workspaceStore: workspaceStore
        ).recordApproval(
            request: XcircuiteCandidatePlanRiskApprovalRequest(
                runID: runID,
                approvalID: approvalID,
                verdict: verdict,
                reviewer: reviewer,
                reviewerKind: reviewerKind,
                note: note
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func executeCandidatePlan(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var candidatePlanArtifactID: String?
        var candidatePlanPath: String?
        var actor = "xcircuite-flow"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--candidate-plan-artifact-id":
                candidatePlanArtifactID = try parser.requiredValue(after: argument)
            case "--candidate-plan-path":
                candidatePlanPath = try parser.requiredValue(after: argument)
            case "--actor":
                actor = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return executeCandidatePlanHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(
                runID: runID,
                candidatePlanArtifactID: candidatePlanArtifactID,
                candidatePlanPath: candidatePlanPath,
                actor: actor
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func runNumericRepairLoop(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var initialCandidateStrategy = "adaptive-bounded-refinement"
        var feedbackCandidateStrategy = "feedback-aware-bounded-refinement"
        var maxCandidates = 9
        var maxIterations = 5
        var synthesisStrategy = "parameter-candidate-to-netlist-edit"
        var verificationMode = "post-execution"
        var actor = "xcircuite-numeric-repair-loop"
        var calibrationPolicy = "disabled"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--initial-candidate-strategy":
                initialCandidateStrategy = try parser.requiredValue(after: argument)
            case "--feedback-candidate-strategy":
                feedbackCandidateStrategy = try parser.requiredValue(after: argument)
            case "--max-candidates":
                maxCandidates = try parser.requiredInt(after: argument)
            case "--max-iterations":
                maxIterations = try parser.requiredInt(after: argument)
            case "--synthesis-strategy":
                synthesisStrategy = try parser.requiredValue(after: argument)
            case "--mode":
                verificationMode = try parser.requiredValue(after: argument)
            case "--actor":
                actor = try parser.requiredValue(after: argument)
            case "--calibration-policy":
                calibrationPolicy = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return runNumericRepairLoopHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteNumericRepairLoopRunner(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).runNumericRepairLoop(
            request: XcircuiteNumericRepairLoopRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                initialCandidateStrategy: initialCandidateStrategy,
                feedbackCandidateStrategy: feedbackCandidateStrategy,
                maxCandidates: maxCandidates,
                maxIterations: maxIterations,
                synthesisStrategy: synthesisStrategy,
                verificationMode: verificationMode,
                actor: actor,
                calibrationPolicy: calibrationPolicy
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func generateImprovementArtifacts(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var numericRepairLoopArtifactID: String?
        var numericRepairLoopPath: String?
        var generatedAt: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--numeric-repair-loop-artifact-id":
                numericRepairLoopArtifactID = try parser.requiredValue(after: argument)
            case "--numeric-repair-loop-path":
                numericRepairLoopPath = try parser.requiredValue(after: argument)
            case "--generated-at":
                generatedAt = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return generateImprovementArtifactsHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteImprovementPlanningArtifactGenerator(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).generateImprovementPlanningArtifacts(
            request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                numericRepairLoopArtifactID: numericRepairLoopArtifactID,
                numericRepairLoopPath: numericRepairLoopPath,
                generatedAt: generatedAt
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func generatePlanningProblem(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var source: XcircuitePlanningProblemSource?
        var summaryArtifactID: String?
        var summaryPath: String?
        var layoutArtifactID: String?
        var layoutPath: String?
        var layoutNetlistPath: String?
        var schematicNetlistPath: String?
        var sourceNetlistPath: String?
        var technologyArtifactID: String?
        var technologyPath: String?
        var metricReportPath: String?
        var repairHintArtifactID: String?
        var repairHintPath: String?
        var actionDomainArtifactID: String?
        var actionDomainPath: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--source":
                source = try parsePlanningProblemSource(try parser.requiredValue(after: argument))
            case "--summary-artifact-id":
                summaryArtifactID = try parser.requiredValue(after: argument)
            case "--summary-path":
                summaryPath = try parser.requiredValue(after: argument)
            case "--layout-artifact-id":
                layoutArtifactID = try parser.requiredValue(after: argument)
            case "--layout-path":
                layoutPath = try parser.requiredValue(after: argument)
            case "--layout-netlist-path":
                layoutNetlistPath = try parser.requiredValue(after: argument)
            case "--schematic-netlist-path":
                schematicNetlistPath = try parser.requiredValue(after: argument)
            case "--source-netlist-path":
                sourceNetlistPath = try parser.requiredValue(after: argument)
            case "--technology-artifact-id":
                technologyArtifactID = try parser.requiredValue(after: argument)
            case "--technology-path":
                technologyPath = try parser.requiredValue(after: argument)
            case "--metric-report-path":
                metricReportPath = try parser.requiredValue(after: argument)
            case "--repair-hint-artifact-id":
                repairHintArtifactID = try parser.requiredValue(after: argument)
            case "--repair-hint-path":
                repairHintPath = try parser.requiredValue(after: argument)
            case "--action-domain-artifact-id":
                actionDomainArtifactID = try parser.requiredValue(after: argument)
            case "--action-domain-path":
                actionDomainPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return generatePlanningProblemHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }
        guard let source else {
            throw XcircuiteFlowCLIError.missingOption("--source")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuitePlanningProblemGenerator(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).generateRepairProblem(
            request: XcircuitePlanningProblemGenerationRequest(
                runID: runID,
                source: source,
                summaryArtifactID: summaryArtifactID,
                summaryPath: summaryPath,
                layoutArtifactID: layoutArtifactID,
                layoutPath: layoutPath,
                layoutNetlistPath: layoutNetlistPath,
                schematicNetlistPath: schematicNetlistPath,
                sourceNetlistPath: sourceNetlistPath,
                technologyArtifactID: technologyArtifactID,
                technologyPath: technologyPath,
                metricReportPath: metricReportPath,
                repairHintArtifactID: repairHintArtifactID,
                repairHintPath: repairHintPath,
                actionDomainArtifactID: actionDomainArtifactID,
                actionDomainPath: actionDomainPath
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func parsePlanningProblemSource(_ value: String) throws -> XcircuitePlanningProblemSource {
        switch value {
        case "drc", "drc-summary":
            return .drcSummary
        case "lvs", "lvs-summary":
            return .lvsSummary
        case "pex", "pex-summary":
            return .pexSummary
        default:
            throw XcircuitePlanningProblemGenerationError.unsupportedSource(value)
        }
    }

    static func formulateRepairPlanningProblem(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var formulationPath: String?
        var problemID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--formulation-path":
                formulationPath = try parser.requiredValue(after: argument)
            case "--problem-id":
                problemID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return formulateRepairPlanningProblemHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }
        guard let formulationPath else {
            throw XcircuiteFlowCLIError.missingOption("--formulation-path")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteRepairPlanFormulationCompiler(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).compile(
            request: XcircuiteRepairPlanFormulationCompilationRequest(
                runID: runID,
                formulationPath: formulationPath,
                problemID: problemID
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func formulateSignoffRepairPlanningProblem(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var drcRepairHintPath: String?
        var lvsRepairHintPath: String?
        var formulationID: String?
        var intentID: String?
        var intent: String?
        var problemID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--drc-repair-hints":
                drcRepairHintPath = try parser.requiredValue(after: argument)
            case "--lvs-repair-hints":
                lvsRepairHintPath = try parser.requiredValue(after: argument)
            case "--formulation-id":
                formulationID = try parser.requiredValue(after: argument)
            case "--intent-id":
                intentID = try parser.requiredValue(after: argument)
            case "--intent":
                intent = try parser.requiredValue(after: argument)
            case "--problem-id":
                problemID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return formulateSignoffRepairPlanningProblemHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let result = try await XcircuiteSignoffRepairFormulationBuilder(
            workspaceStore: workspaceStore,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        ).compile(
            request: XcircuiteSignoffRepairFormulationRequest(
                runID: runID,
                drcRepairHintPath: drcRepairHintPath,
                lvsRepairHintPath: lvsRepairHintPath,
                formulationID: formulationID,
                intentID: intentID,
                intent: intent,
                problemID: problemID
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }
}
