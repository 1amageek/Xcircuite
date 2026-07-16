import Foundation
import DesignFlowKernel

public struct XcircuiteSelectedSuggestedCommandResolver: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    public func resolve(
        request: XcircuiteSelectedSuggestedCommandResolutionRequest,
        projectRoot: URL
    ) async throws -> XcircuiteResolvedSuggestedCommand {
        let selection = try await selectedCommand(
            runID: request.runID,
            commandID: request.commandID
        )
        try validate(selection: selection, request: request, projectRoot: projectRoot)
        guard let commandName = selection.arguments.first else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.missingCommandName(
                commandID: selection.commandID
            )
        }
        try validateAllowedArguments(
            commandName: commandName,
            arguments: selection.arguments,
            request: request,
            projectRoot: projectRoot
        )

        return XcircuiteResolvedSuggestedCommand(
            selection: selection,
            commandName: commandName,
            dispatchArguments: selection.arguments
        )
    }

    private func selectedCommand(
        runID: String,
        commandID: String?
    ) async throws -> FlowSuggestedCommandSelection {
        let selections = try await workspaceStore.loadSuggestedCommandSelections(runID: runID)
        let matching = selections.filter { selection in
            guard selection.status == .succeeded else {
                return false
            }
            guard let commandID else {
                return true
            }
            return selection.commandID == commandID
        }
        guard let selection = matching.last else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.noSelection(
                runID: runID,
                commandID: commandID
            )
        }
        return selection
    }

    private func validate(
        selection: FlowSuggestedCommandSelection,
        request: XcircuiteSelectedSuggestedCommandResolutionRequest,
        projectRoot: URL
    ) throws {
        guard selection.executable == "xcircuite-flow" else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedExecutable(
                selection.executable
            )
        }
        guard selection.readiness == "ready" else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedReadiness(
                selection.readiness
            )
        }
        guard selection.runID == request.runID else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: selection.runID
            )
        }
        let selectedRunID = try requiredOption("--run-id", in: selection)
        guard selectedRunID == request.runID else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: selectedRunID
            )
        }
        let selectedProjectRoot = try requiredOption("--project-root", in: selection)
        let expectedProjectRoot = normalizedPath(projectRoot)
        guard normalizedPath(URL(filePath: selectedProjectRoot)) == expectedProjectRoot else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.mismatchedProjectRoot(
                expected: expectedProjectRoot,
                actual: selectedProjectRoot
            )
        }
    }

    private func requiredOption(
        _ option: String,
        in selection: FlowSuggestedCommandSelection
    ) throws -> String {
        guard let index = selection.arguments.firstIndex(of: option),
              selection.arguments.indices.contains(index + 1) else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.missingRequiredOption(
                commandID: selection.commandID,
                option: option
            )
        }
        return selection.arguments[index + 1]
    }

    private func validateAllowedArguments(
        commandName: String,
        arguments: [String],
        request: XcircuiteSelectedSuggestedCommandResolutionRequest,
        projectRoot: URL
    ) throws {
        guard allowedCommands.contains(commandName) else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedCommand(commandName)
        }

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--project-root":
                let value = try requiredArgumentValue(
                    option: argument,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                guard normalizedPath(URL(filePath: value)) == normalizedPath(projectRoot) else {
                    throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                        commandName: commandName,
                        arguments: arguments
                    )
                }
                index += 2
            case "--run-id":
                let value = try requiredArgumentValue(
                    option: argument,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                guard value == request.runID else {
                    throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                        commandName: commandName,
                        arguments: arguments
                    )
                }
                index += 2
            case "--pretty":
                index += 1
            case "--mode" where commandName == "verify-candidate-plan":
                try validateAllowedValue(
                    option: argument,
                    index: index,
                    commandName: commandName,
                    arguments: arguments,
                    allowedValues: allowedVerificationModes
                )
                index += 2
            case "--mode" where commandName == "run-numeric-repair-loop":
                try validateAllowedValue(
                    option: argument,
                    index: index,
                    commandName: commandName,
                    arguments: arguments,
                    allowedValues: allowedVerificationModes
                )
                index += 2
            case "--calibration-policy" where [
                "generate-candidate-plan",
                "run-symbolic-planner-family",
                "run-numeric-repair-loop",
            ].contains(commandName):
                try validateAllowedValue(
                    option: argument,
                    index: index,
                    commandName: commandName,
                    arguments: arguments,
                    allowedValues: allowedCalibrationPolicies
                )
                index += 2
            case let option where artifactIDOptions(for: commandName).contains(option):
                try validateArtifactIDValue(
                    option: option,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                index += 2
            case let option where projectRelativePathOptions(for: commandName).contains(option):
                try validateProjectRelativeArtifactPath(
                    option: option,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                index += 2
            case let option where textValueOptions(for: commandName).contains(option):
                _ = try requiredArgumentValue(
                    option: option,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                index += 2
            case let option where integerValueOptions(for: commandName).contains(option):
                try validateIntegerValue(
                    option: option,
                    index: index,
                    commandName: commandName,
                    arguments: arguments
                )
                index += 2
            case let option where flagOptions(for: commandName).contains(option):
                index += 1
            default:
                throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                    commandName: commandName,
                    arguments: arguments
                )
            }
        }
    }

    private func requiredArgumentValue(
        option: String,
        index: Int,
        commandName: String,
        arguments: [String]
    ) throws -> String {
        guard arguments.indices.contains(index + 1) else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
        let value = arguments[index + 1]
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("--") else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
        return value
    }

    private func validateAllowedValue(
        option: String,
        index: Int,
        commandName: String,
        arguments: [String],
        allowedValues: Set<String>
    ) throws {
        let value = try requiredArgumentValue(
            option: option,
            index: index,
            commandName: commandName,
            arguments: arguments
        )
        guard allowedValues.contains(value) else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
    }

    private func validateArtifactIDValue(
        option: String,
        index: Int,
        commandName: String,
        arguments: [String]
    ) throws {
        let value = try requiredArgumentValue(
            option: option,
            index: index,
            commandName: commandName,
            arguments: arguments
        )
        do {
            try FlowIdentifierValidator().validate(value, kind: .artifactID)
        } catch {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
    }

    private func validateProjectRelativeArtifactPath(
        option: String,
        index: Int,
        commandName: String,
        arguments: [String]
    ) throws {
        let value = try requiredArgumentValue(
            option: option,
            index: index,
            commandName: commandName,
            arguments: arguments
        )
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let isProjectArtifactPath = value.hasPrefix(".xcircuite/")
            && !value.hasPrefix("/")
            && !value.hasPrefix("~")
            && !value.contains("://")
            && !components.contains("")
            && !components.contains(".")
            && !components.contains("..")
        guard isProjectArtifactPath else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
    }

    private func validateIntegerValue(
        option: String,
        index: Int,
        commandName: String,
        arguments: [String]
    ) throws {
        let value = try requiredArgumentValue(
            option: option,
            index: index,
            commandName: commandName,
            arguments: arguments
        )
        guard let parsedValue = Int(value), parsedValue >= 0 else {
            throw XcircuiteSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandName: commandName,
                arguments: arguments
            )
        }
    }

    private func artifactIDOptions(for commandName: String) -> Set<String> {
        switch commandName {
        case "validate-planning-problem":
            ["--problem-artifact-id", "--action-domain-artifact-id"]
        case "audit-problem-translation":
            ["--problem-artifact-id"]
        case "generate-candidate-plan", "run-symbolic-planner-family":
            [
                "--problem-artifact-id",
                "--rejected-plans-artifact-id",
                "--metric-threshold-profile-artifact-id",
                "--cost-calibration-artifact-id",
                "--pareto-candidates-artifact-id",
            ]
        case "execute-candidate-plan", "verify-candidate-plan":
            ["--candidate-plan-artifact-id"]
        case "generate-parameter-candidates":
            [
                "--problem-artifact-id",
                "--rejected-plans-artifact-id",
                "--previous-parameter-candidates-artifact-id",
                "--metric-threshold-profile-artifact-id",
                "--cost-calibration-artifact-id",
                "--pareto-candidates-artifact-id",
            ]
        case "synthesize-parameter-candidate-plan":
            ["--problem-artifact-id", "--parameter-candidates-artifact-id", "--rejected-plans-artifact-id"]
        case "run-numeric-repair-loop":
            ["--problem-artifact-id"]
        case "compare-symbolic-planner-solver-family":
            ["--validation-artifact-id"]
        case "promote-symbolic-planner-solver-family-selection":
            ["--comparison-artifact-id"]
        case "generate-improvement-artifacts":
            ["--problem-artifact-id", "--numeric-repair-loop-artifact-id"]
        default:
            []
        }
    }

    private func projectRelativePathOptions(for commandName: String) -> Set<String> {
        switch commandName {
        case "validate-planning-problem":
            ["--problem-path", "--action-domain-path"]
        case "audit-problem-translation":
            ["--problem-path"]
        case "generate-candidate-plan", "run-symbolic-planner-family":
            [
                "--problem-path",
                "--rejected-plans-path",
                "--metric-threshold-profile-path",
                "--cost-calibration-path",
                "--pareto-candidates-path",
            ]
        case "execute-candidate-plan", "verify-candidate-plan":
            ["--candidate-plan-path"]
        case "generate-parameter-candidates":
            [
                "--problem-path",
                "--rejected-plans-path",
                "--previous-parameter-candidates-path",
                "--metric-threshold-profile-path",
                "--cost-calibration-path",
                "--pareto-candidates-path",
            ]
        case "synthesize-parameter-candidate-plan":
            ["--problem-path", "--parameter-candidates-path", "--rejected-plans-path"]
        case "run-numeric-repair-loop":
            ["--problem-path"]
        case "compare-symbolic-planner-solver-family":
            ["--validation-path"]
        case "promote-symbolic-planner-solver-family-selection":
            ["--comparison-path"]
        case "generate-improvement-artifacts":
            ["--problem-path", "--numeric-repair-loop-path"]
        default:
            []
        }
    }

    private func textValueOptions(for commandName: String) -> Set<String> {
        switch commandName {
        case "generate-candidate-plan", "generate-parameter-candidates":
            ["--strategy"]
        case "run-symbolic-planner-family":
            ["--family-run-id", "--strategy", "--selection-policy"]
        case "execute-candidate-plan":
            ["--actor"]
        case "synthesize-parameter-candidate-plan":
            ["--candidate-id", "--strategy"]
        case "run-numeric-repair-loop":
            ["--initial-candidate-strategy", "--feedback-candidate-strategy", "--synthesis-strategy", "--actor"]
        case "compare-symbolic-planner-solver-family":
            ["--comparison-id", "--selection-policy"]
        case "promote-symbolic-planner-solver-family-selection":
            ["--comparison-id"]
        case "generate-improvement-artifacts":
            ["--generated-at"]
        default:
            []
        }
    }

    private func integerValueOptions(for commandName: String) -> Set<String> {
        switch commandName {
        case "generate-parameter-candidates":
            ["--max-candidates"]
        case "synthesize-parameter-candidate-plan":
            ["--rank"]
        case "run-numeric-repair-loop":
            ["--max-candidates", "--max-iterations"]
        case "promote-symbolic-planner-solver-family-selection":
            ["--candidate-index"]
        default:
            []
        }
    }

    private func flagOptions(for commandName: String) -> Set<String> {
        switch commandName {
        case "synthesize-parameter-candidate-plan":
            ["--include-rejected-candidates"]
        case "promote-symbolic-planner-solver-family-selection":
            ["--allow-failing-validation", "--skip-verification"]
        default:
            []
        }
    }

    private var allowedCommands: Set<String> {
        [
            "audit-problem-translation",
            "validate-planning-problem",
            "generate-candidate-plan",
            "run-symbolic-planner-family",
            "execute-candidate-plan",
            "verify-candidate-plan",
            "generate-parameter-candidates",
            "synthesize-parameter-candidate-plan",
            "run-numeric-repair-loop",
            "compare-symbolic-planner-solver-family",
            "promote-symbolic-planner-solver-family-selection",
            "generate-improvement-artifacts",
        ]
    }

    private var allowedVerificationModes: Set<String> {
        ["preflight", "post-execution"]
    }

    private var allowedCalibrationPolicies: Set<String> {
        ["disabled", "cp7-feedback"]
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
