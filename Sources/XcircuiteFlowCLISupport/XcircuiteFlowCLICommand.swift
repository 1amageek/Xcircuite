import Foundation
import Xcircuite
import DesignFlowKernel

public enum XcircuiteFlowCLICommand {
    public static func run(arguments: [String]) async throws -> String {
        guard let command = arguments.first else {
            throw XcircuiteFlowCLIError.usage
        }

        switch command {
        case "run":
            return try await runFlow(arguments: Array(arguments.dropFirst()))
        case "resume-run":
            return try await resumeRun(arguments: Array(arguments.dropFirst()))
        case "attach-evidence":
            return try attachEvidence(arguments: Array(arguments.dropFirst()))
        case "scaffold-run":
            return try scaffoldRun(arguments: Array(arguments.dropFirst()))
        case "validate":
            return try validateSpecs(arguments: Array(arguments.dropFirst()))
        case "inspect-toolchain-profile":
            return try inspectToolchainProfile(arguments: Array(arguments.dropFirst()))
        case "inspect-technology-catalog":
            return try inspectTechnologyCatalog(arguments: Array(arguments.dropFirst()))
        case "inspect-platform-capabilities":
            return try inspectPlatformCapabilities(arguments: Array(arguments.dropFirst()))
        case "compare-simulation-golden":
            return try compareSimulationGolden(arguments: Array(arguments.dropFirst()))
        case "qualify-simulation-golden-corpus":
            return try await qualifySimulationGoldenCorpus(arguments: Array(arguments.dropFirst()))
        case "generate-planning-problem":
            return try await generatePlanningProblem(arguments: Array(arguments.dropFirst()))
        case "formulate-repair-planning-problem":
            return try await formulateRepairPlanningProblem(arguments: Array(arguments.dropFirst()))
        case "formulate-signoff-repair-planning-problem":
            return try await formulateSignoffRepairPlanningProblem(arguments: Array(arguments.dropFirst()))
        case "collect-generated-layout-signoff-corpus":
            return try await collectGeneratedLayoutSignoffCorpus(arguments: Array(arguments.dropFirst()))
        case "qualify-generated-layout-signoff-corpus":
            return try await qualifyGeneratedLayoutSignoffCorpus(arguments: Array(arguments.dropFirst()))
        case "attach-generated-layout-ready-oracle-evidence":
            return try await attachGeneratedLayoutReadyOracleEvidence(arguments: Array(arguments.dropFirst()))
        case "audit-generated-layout-signoff-corpus-coverage":
            return try await auditGeneratedLayoutSignoffCorpusCoverage(arguments: Array(arguments.dropFirst()))
        case "assess-generated-layout-signoff-promotion":
            return try await assessGeneratedLayoutSignoffPromotion(arguments: Array(arguments.dropFirst()))
        case "collect-generated-layout-failure-ladder":
            return try await collectGeneratedLayoutFailureLadder(arguments: Array(arguments.dropFirst()))
        case "audit-generated-layout-failure-ladder-coverage":
            return try await auditGeneratedLayoutFailureLadderCoverage(arguments: Array(arguments.dropFirst()))
        case "validate-planning-problem":
            return try await validatePlanningProblem(arguments: Array(arguments.dropFirst()))
        case "audit-problem-translation":
            return try await auditProblemTranslation(arguments: Array(arguments.dropFirst()))
        case "generate-candidate-plan":
            return try await generateCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-family":
            return try await runSymbolicPlannerFamily(arguments: Array(arguments.dropFirst()))
        case "export-symbolic-planner-problem":
            return try await exportSymbolicPlannerProblem(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-solver":
            return try await runSymbolicPlannerSolver(arguments: Array(arguments.dropFirst()))
        case "qualify-symbolic-planner-solver":
            return try await qualifySymbolicPlannerSolver(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-solver-family":
            return try await runSymbolicPlannerSolverFamily(arguments: Array(arguments.dropFirst()))
        case "discover-installed-symbolic-planner-solvers":
            return try await discoverInstalledSymbolicPlannerSolvers(arguments: Array(arguments.dropFirst()))
        case "compare-symbolic-planner-solver-family":
            return try await compareSymbolicPlannerSolverFamily(arguments: Array(arguments.dropFirst()))
        case "promote-symbolic-planner-solver-family-selection":
            return try await promoteSymbolicPlannerSolverFamilySelection(arguments: Array(arguments.dropFirst()))
        case "qualify-symbolic-planner-solver-corpus":
            return try await qualifySymbolicPlannerSolverCorpus(arguments: Array(arguments.dropFirst()))
        case "symbolic-planner-feature-matrix":
            return try symbolicPlannerFeatureMatrix(arguments: Array(arguments.dropFirst()))
        case "import-symbolic-planner-plan":
            return try await importSymbolicPlannerPlan(arguments: Array(arguments.dropFirst()))
        case "generate-parameter-candidates":
            return try await generateParameterCandidates(arguments: Array(arguments.dropFirst()))
        case "synthesize-parameter-candidate-plan":
            return try await synthesizeParameterCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "approve-candidate-plan-risk":
            return try await approveCandidatePlanRisk(arguments: Array(arguments.dropFirst()))
        case "verify-candidate-plan":
            return try await verifyCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "execute-candidate-plan":
            return try await executeCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "run-numeric-repair-loop":
            return try await runNumericRepairLoop(arguments: Array(arguments.dropFirst()))
        case "generate-improvement-artifacts":
            return try await generateImprovementArtifacts(arguments: Array(arguments.dropFirst()))
        case "qualify-verified-improvement-corpus":
            return try await qualifyVerifiedImprovementCorpus(arguments: Array(arguments.dropFirst()))
        case "run-selected-suggested-command":
            return try await runSelectedSuggestedCommand(arguments: Array(arguments.dropFirst()))
        case "summarize-loop":
            return try await summarizeLoop(arguments: Array(arguments.dropFirst()))
        case "evaluate-run-guard":
            return try await evaluateRunGuard(arguments: Array(arguments.dropFirst()))
        case "compare-artifacts":
            return try await compareArtifacts(arguments: Array(arguments.dropFirst()))
        case "inspect-run":
            return try await inspectRun(arguments: Array(arguments.dropFirst()))
        case "review-run":
            return try await reviewRun(arguments: Array(arguments.dropFirst()))
        case "build-stage-artifact-ladder":
            return try await buildStageArtifactLadder(arguments: Array(arguments.dropFirst()))
        case "build-decision-packet":
            return try await buildDecisionPacket(arguments: Array(arguments.dropFirst()))
        case "validate-decision-packet":
            return try await validateDecisionPacket(arguments: Array(arguments.dropFirst()))
        case "build-release-envelope":
            return try await buildReleaseEnvelope(arguments: Array(arguments.dropFirst()))
        case "collect-release-evidence":
            return try await collectReleaseEvidence(arguments: Array(arguments.dropFirst()))
        case "build-retention-index":
            return try await buildRetentionIndex(arguments: Array(arguments.dropFirst()))
        case "validate-retention-index":
            return try await validateRetentionIndex(arguments: Array(arguments.dropFirst()))
        case "approve-gate":
            return try await approveGate(arguments: Array(arguments.dropFirst()))
        case "request-cancel":
            return try await requestCancellation(arguments: Array(arguments.dropFirst()))
        case "progress-run":
            return try await progressRun(arguments: Array(arguments.dropFirst()))
        case "write-opamp-evaluation-profile":
            return try writeOpAmpEvaluationProfile(arguments: Array(arguments.dropFirst()))
        case "write-opamp-spec":
            return try writeOpAmpSpec(arguments: Array(arguments.dropFirst()))
        case "list-opamp-topologies":
            return try listOpAmpTopologies(arguments: Array(arguments.dropFirst()))
        case "size-opamp":
            return try await sizeOpAmp(arguments: Array(arguments.dropFirst()))
        case "validate-opamp-simulation-decks":
            return try await validateOpAmpSimulationDecks(arguments: Array(arguments.dropFirst()))
        case "run-opamp-simulation-decks":
            return try await runOpAmpSimulationDecks(arguments: Array(arguments.dropFirst()))
        case "extract-opamp-waveform-metrics":
            return try await extractOpAmpWaveformMetrics(arguments: Array(arguments.dropFirst()))
        case "merge-opamp-metric-extractions":
            return try await mergeOpAmpMetricExtractions(arguments: Array(arguments.dropFirst()))
        case "evaluate-opamp":
            return try await evaluateOpAmp(arguments: Array(arguments.dropFirst()))
        case "compare-opamp-post-layout":
            return try await compareOpAmpPostLayout(arguments: Array(arguments.dropFirst()))
        case "--help", "-h", "help":
            return helpText
        default:
            throw XcircuiteFlowCLIError.unknownCommand(command)
        }
    }
}
