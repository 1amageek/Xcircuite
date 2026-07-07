import Foundation

public enum XcircuiteSelectedSuggestedCommandResolutionError: Error, LocalizedError, Equatable {
    case noSelection(runID: String, commandID: String?)
    case unsupportedExecutable(String)
    case unsupportedReadiness(String)
    case missingCommandName(commandID: String)
    case unsupportedCommand(String)
    case missingRequiredOption(commandID: String, option: String)
    case mismatchedRunID(expected: String, actual: String)
    case mismatchedProjectRoot(expected: String, actual: String)
    case unsupportedArguments(commandName: String, arguments: [String])

    public var errorDescription: String? {
        switch self {
        case .noSelection(let runID, let commandID):
            if let commandID {
                "No selected suggested command was found for run \(runID) and command \(commandID)."
            } else {
                "No selected suggested command was found for run \(runID)."
            }
        case .unsupportedExecutable(let executable):
            "Selected suggested command uses unsupported executable: \(executable)"
        case .unsupportedReadiness(let readiness):
            "Selected suggested command is not ready to run: \(readiness)"
        case .missingCommandName(let commandID):
            "Selected suggested command \(commandID) has no command name."
        case .unsupportedCommand(let commandName):
            "Selected suggested command is not in the xcircuite-flow allowlist: \(commandName)"
        case .missingRequiredOption(let commandID, let option):
            "Selected suggested command \(commandID) is missing required option \(option)."
        case .mismatchedRunID(let expected, let actual):
            "Selected suggested command run ID mismatch. Expected \(expected), got \(actual)."
        case .mismatchedProjectRoot(let expected, let actual):
            "Selected suggested command project root mismatch. Expected \(expected), got \(actual)."
        case .unsupportedArguments(let commandName, let arguments):
            "Selected suggested command \(commandName) contains unsupported arguments: \(arguments.joined(separator: " "))"
        }
    }
}
