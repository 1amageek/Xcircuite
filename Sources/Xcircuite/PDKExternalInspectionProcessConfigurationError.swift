import Foundation

public enum PDKExternalInspectionProcessConfigurationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyExecutablePath
    case executablePathMustBeAbsolute(String)
    case invalidTimeout(Double)
    case emptyWorkingDirectoryPath
    case unsafeWorkingDirectoryPath(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported external PDK process configuration schema version: \(version)."
        case .emptyExecutablePath:
            "External PDK process executablePath must not be empty."
        case .executablePathMustBeAbsolute(let path):
            "External PDK process executablePath must be absolute: \(path)."
        case .invalidTimeout(let timeout):
            "External PDK process timeout must be a positive finite number: \(timeout)."
        case .emptyWorkingDirectoryPath:
            "External PDK process workingDirectoryPath must not be empty."
        case .unsafeWorkingDirectoryPath(let path):
            "External PDK process workingDirectoryPath must not contain parent traversal: \(path)."
        }
    }
}
