import DesignFlowKernel
import Foundation
import Xcircuite
import DesignFlowKernel

extension XcircuiteFlowCLICommand {
    static func runSelectedSuggestedCommand(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var commandID: String?

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--command-id":
                commandID = try parser.requiredValue(after: argument)
            case "--help", "-h":
                return runSelectedSuggestedCommandHelpText
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

        let resolved: XcircuiteResolvedSuggestedCommand
        do {
            let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
            resolved = try await XcircuiteSelectedSuggestedCommandResolver(
                workspaceStore: workspaceStore
            ).resolve(
                request: XcircuiteSelectedSuggestedCommandResolutionRequest(
                    runID: runID,
                    commandID: commandID
                ),
                projectRoot: projectRoot
            )
        } catch let error as XcircuiteSelectedSuggestedCommandResolutionError {
            throw XcircuiteFlowCLIError.selectedSuggestedCommandNotRunnable(
                error.localizedDescription
            )
        }
        return try await dispatchResolvedSuggestedCommand(resolved)
    }

    static func dispatchResolvedSuggestedCommand(
        _ resolved: XcircuiteResolvedSuggestedCommand
    ) async throws -> String {
        let arguments = Array(resolved.dispatchArguments.dropFirst())
        switch resolved.commandName {
        case "validate-planning-problem":
            return try await validatePlanningProblem(arguments: arguments)
        case "audit-problem-translation":
            return try await auditProblemTranslation(arguments: arguments)
        case "generate-candidate-plan":
            return try await generateCandidatePlan(arguments: arguments)
        case "run-symbolic-planner-family":
            return try await runSymbolicPlannerFamily(arguments: arguments)
        case "compare-symbolic-planner-solver-family":
            return try await compareSymbolicPlannerSolverFamily(arguments: arguments)
        case "promote-symbolic-planner-solver-family-selection":
            return try await promoteSymbolicPlannerSolverFamilySelection(arguments: arguments)
        case "execute-candidate-plan":
            return try await executeCandidatePlan(arguments: arguments)
        case "verify-candidate-plan":
            return try await verifyCandidatePlan(arguments: arguments)
        case "generate-parameter-candidates":
            return try await generateParameterCandidates(arguments: arguments)
        case "synthesize-parameter-candidate-plan":
            return try await synthesizeParameterCandidatePlan(arguments: arguments)
        case "run-numeric-repair-loop":
            return try await runNumericRepairLoop(arguments: arguments)
        case "generate-improvement-artifacts":
            return try await generateImprovementArtifacts(arguments: arguments)
        default:
            throw XcircuiteFlowCLIError.selectedSuggestedCommandNotRunnable(
                "Unsupported command \(resolved.commandName)"
            )
        }
    }

    struct QualificationRecordAttachmentOutput: Sendable, Hashable, Codable {
        var stageID: String
        var recordArtifactID: String
        var outputPath: String?
    }

    struct ValidationOutput: Sendable, Hashable, Codable {
        var status: String
        var validated: [String]
        var runSpecPath: String?
        var runtimeConfigPath: String?
        var runStageCount: Int?
        var runtimeExecutorCount: Int?
    }
}
