import DesignFlowKernel
import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func runSelectedSuggestedAction(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var actionID: String?

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--action-id":
                actionID = try parser.requiredValue(after: argument)
            case "--help", "-h":
                return runSelectedSuggestedActionHelpText
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

        let resolved: XcircuiteResolvedSuggestedAction
        do {
            let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
            resolved = try await XcircuiteSelectedSuggestedActionResolver(
                workspaceStore: workspaceStore
            ).resolve(
                request: XcircuiteSelectedSuggestedActionResolutionRequest(
                    runID: runID,
                    actionID: actionID
                )
            )
        } catch let error as XcircuiteSelectedSuggestedActionResolutionError {
            throw XcircuiteFlowCLIError.selectedSuggestedActionNotRunnable(
                error.localizedDescription
            )
        }
        return try await dispatchResolvedSuggestedAction(resolved)
    }

    static func dispatchResolvedSuggestedAction(
        _ resolved: XcircuiteResolvedSuggestedAction
    ) async throws -> String {
        let arguments = resolved.dispatchArguments
        switch resolved.command {
        case .summarizeLoop:
            return try await summarizeLoop(arguments: arguments)
        case .inspectRun:
            return try await inspectRun(arguments: arguments)
        case .reviewRun:
            return try await reviewRun(arguments: arguments)
        case .evaluateRunGuard:
            return try await evaluateRunGuard(arguments: arguments)
        case .validatePlanningProblem:
            return try await validatePlanningProblem(arguments: arguments)
        case .auditProblemTranslation:
            return try await auditProblemTranslation(arguments: arguments)
        case .generateCandidatePlan:
            return try await generateCandidatePlan(arguments: arguments)
        case .executeCandidatePlan:
            return try await executeCandidatePlan(arguments: arguments)
        case .verifyCandidatePlan:
            return try await verifyCandidatePlan(arguments: arguments)
        case .generateParameterCandidates:
            return try await generateParameterCandidates(arguments: arguments)
        case .synthesizeParameterCandidatePlan:
            return try await synthesizeParameterCandidatePlan(arguments: arguments)
        case .runNumericRepairLoop:
            return try await runNumericRepairLoop(arguments: arguments)
        case .buildStageArtifactLadder:
            return try await buildStageArtifactLadder(arguments: arguments)
        case .validateDecisionPacket:
            return try await validateDecisionPacket(arguments: arguments)
        case .buildReleaseEnvelope:
            return try await buildReleaseEnvelope(arguments: arguments)
        }
    }
}
