import Foundation

public enum XcircuiteWorkspaceStoreError: Error, Sendable, Equatable, LocalizedError {
    case projectRootIsNotAbsolute
    case projectRootIsNotDirectory
    case invalidRelativePath(String)
    case pathOutsideWorkspace(String)
    case missingArtifact(String)
    case readFailed(String)
    case writeFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .projectRootIsNotAbsolute:
            "Project root must be an absolute file URL."
        case .projectRootIsNotDirectory:
            "Project root must identify a directory."
        case .invalidRelativePath(let path):
            "Workspace path is not relative: \(path)"
        case .pathOutsideWorkspace(let path):
            "Workspace path escapes the .xcircuite boundary: \(path)"
        case .missingArtifact(let path):
            "Workspace artifact does not exist: \(path)"
        case .readFailed(let message):
            "Workspace read failed: \(message)"
        case .writeFailed(let message):
            "Workspace write failed: \(message)"
        case .encodeFailed(let message):
            "Workspace encoding failed: \(message)"
        case .decodeFailed(let message):
            "Workspace decoding failed: \(message)"
        }
    }
}
