import Foundation

public enum ElectricalSignoffOracleProcessConfigurationError: Error, Sendable, Hashable, Codable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyExecutablePath
    case executablePathMustBeAbsolute(String)
    case invalidTimeout(Double)
    case emptyWorkingDirectoryPath
    case unsafeWorkingDirectoryPath(String)
    case missingArgumentPlaceholder(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Electrical oracle process configuration schema version is unsupported: \(version)."
        case .emptyExecutablePath:
            return "Electrical oracle process executable path must not be empty."
        case .executablePathMustBeAbsolute(let path):
            return "Electrical oracle process executable path must be absolute: \(path)."
        case .invalidTimeout(let seconds):
            return "Electrical oracle process timeout must be finite and positive: \(seconds)."
        case .emptyWorkingDirectoryPath:
            return "Electrical oracle process working directory path must not be empty."
        case .unsafeWorkingDirectoryPath(let path):
            return "Electrical oracle process working directory path is unsafe: \(path)."
        case .missingArgumentPlaceholder(let placeholder):
            return "Electrical oracle process arguments must contain the placeholder \(placeholder)."
        }
    }
}
