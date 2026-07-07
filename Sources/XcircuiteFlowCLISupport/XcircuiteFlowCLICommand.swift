import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

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
            return try generatePlanningProblem(arguments: Array(arguments.dropFirst()))
        case "formulate-repair-planning-problem":
            return try formulateRepairPlanningProblem(arguments: Array(arguments.dropFirst()))
        case "formulate-signoff-repair-planning-problem":
            return try formulateSignoffRepairPlanningProblem(arguments: Array(arguments.dropFirst()))
        case "collect-generated-layout-signoff-corpus":
            return try collectGeneratedLayoutSignoffCorpus(arguments: Array(arguments.dropFirst()))
        case "qualify-generated-layout-signoff-corpus":
            return try qualifyGeneratedLayoutSignoffCorpus(arguments: Array(arguments.dropFirst()))
        case "attach-generated-layout-ready-oracle-evidence":
            return try attachGeneratedLayoutReadyOracleEvidence(arguments: Array(arguments.dropFirst()))
        case "audit-generated-layout-signoff-corpus-coverage":
            return try auditGeneratedLayoutSignoffCorpusCoverage(arguments: Array(arguments.dropFirst()))
        case "assess-generated-layout-signoff-promotion":
            return try assessGeneratedLayoutSignoffPromotion(arguments: Array(arguments.dropFirst()))
        case "collect-generated-layout-failure-ladder":
            return try collectGeneratedLayoutFailureLadder(arguments: Array(arguments.dropFirst()))
        case "audit-generated-layout-failure-ladder-coverage":
            return try auditGeneratedLayoutFailureLadderCoverage(arguments: Array(arguments.dropFirst()))
        case "validate-planning-problem":
            return try validatePlanningProblem(arguments: Array(arguments.dropFirst()))
        case "audit-problem-translation":
            return try auditProblemTranslation(arguments: Array(arguments.dropFirst()))
        case "generate-candidate-plan":
            return try generateCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-family":
            return try runSymbolicPlannerFamily(arguments: Array(arguments.dropFirst()))
        case "export-symbolic-planner-problem":
            return try exportSymbolicPlannerProblem(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-solver":
            return try await runSymbolicPlannerSolver(arguments: Array(arguments.dropFirst()))
        case "qualify-symbolic-planner-solver":
            return try await qualifySymbolicPlannerSolver(arguments: Array(arguments.dropFirst()))
        case "run-symbolic-planner-solver-family":
            return try await runSymbolicPlannerSolverFamily(arguments: Array(arguments.dropFirst()))
        case "discover-installed-symbolic-planner-solvers":
            return try discoverInstalledSymbolicPlannerSolvers(arguments: Array(arguments.dropFirst()))
        case "compare-symbolic-planner-solver-family":
            return try compareSymbolicPlannerSolverFamily(arguments: Array(arguments.dropFirst()))
        case "promote-symbolic-planner-solver-family-selection":
            return try await promoteSymbolicPlannerSolverFamilySelection(arguments: Array(arguments.dropFirst()))
        case "qualify-symbolic-planner-solver-corpus":
            return try await qualifySymbolicPlannerSolverCorpus(arguments: Array(arguments.dropFirst()))
        case "symbolic-planner-feature-matrix":
            return try symbolicPlannerFeatureMatrix(arguments: Array(arguments.dropFirst()))
        case "import-symbolic-planner-plan":
            return try importSymbolicPlannerPlan(arguments: Array(arguments.dropFirst()))
        case "generate-parameter-candidates":
            return try generateParameterCandidates(arguments: Array(arguments.dropFirst()))
        case "synthesize-parameter-candidate-plan":
            return try synthesizeParameterCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "approve-candidate-plan-risk":
            return try approveCandidatePlanRisk(arguments: Array(arguments.dropFirst()))
        case "verify-candidate-plan":
            return try await verifyCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "execute-candidate-plan":
            return try await executeCandidatePlan(arguments: Array(arguments.dropFirst()))
        case "run-numeric-repair-loop":
            return try await runNumericRepairLoop(arguments: Array(arguments.dropFirst()))
        case "generate-improvement-artifacts":
            return try generateImprovementArtifacts(arguments: Array(arguments.dropFirst()))
        case "qualify-verified-improvement-corpus":
            return try qualifyVerifiedImprovementCorpus(arguments: Array(arguments.dropFirst()))
        case "run-selected-suggested-command":
            return try await runSelectedSuggestedCommand(arguments: Array(arguments.dropFirst()))
        case "--help", "-h", "help":
            return helpText
        default:
            throw XcircuiteFlowCLIError.unknownCommand(command)
        }
    }
}
