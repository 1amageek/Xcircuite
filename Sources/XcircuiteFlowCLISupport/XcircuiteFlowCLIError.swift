import Foundation

public enum XcircuiteFlowCLIError: Error {
    case usage
    case unknownCommand(String)
    case unknownOption(String)
    case missingOption(String)
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case selectedSuggestedActionNotRunnable(String)
    case encodeFailed(String)
    case readFailed(String)
    case writeFailed(String)

    public var exitCode: Int {
        switch self {
        case .usage, .unknownCommand, .unknownOption, .missingOption, .missingValue, .invalidValue,
             .selectedSuggestedActionNotRunnable:
            64
        case .encodeFailed, .readFailed, .writeFailed:
            1
        }
    }

    public var message: String {
        switch self {
        case .usage:
            XcircuiteFlowCLICommand.usageText
        case .unknownCommand(let command):
            "Unknown command: \(command)"
        case .unknownOption(let option):
            "Unknown option: \(option)"
        case .missingOption(let option):
            "Missing required option: \(option)"
        case .missingValue(let option):
            "Missing value after option: \(option)"
        case .invalidValue(let option, let value):
            "Invalid value after option \(option): \(value)"
        case .selectedSuggestedActionNotRunnable(let reason):
            "Selected suggested action is not runnable: \(reason)"
        case .encodeFailed(let reason):
            "Failed to encode output: \(reason)"
        case .readFailed(let reason):
            "Failed to read input: \(reason)"
        case .writeFailed(let reason):
            "Failed to write output: \(reason)"
        }
    }
}
