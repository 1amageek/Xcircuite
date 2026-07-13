import Foundation

public enum XcircuiteMigrationError: Error, Sendable, Equatable, LocalizedError {
    case workspaceReadFailed(String)
    case invalidJSON(String)
    case workspaceWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .workspaceReadFailed(let message):
            "Could not enumerate .xcircuite data: \(message)"
        case .invalidJSON(let path):
            "Migration encountered invalid JSON: \(path)"
        case .workspaceWriteFailed(let message):
            "Could not persist migrated .xcircuite data: \(message)"
        }
    }
}
