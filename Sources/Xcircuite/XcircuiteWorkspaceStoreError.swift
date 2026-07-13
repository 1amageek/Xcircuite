import Foundation
import CircuiteFoundation

public enum XcircuiteWorkspaceStoreError: Error, Sendable, Equatable, LocalizedError {
    case projectRootIsNotAbsolute
    case projectRootIsNotDirectory
    case invalidRelativePath(String)
    case pathOutsideWorkspace(String)
    case invalidArtifactLocation(String)
    case missingArtifact(String)
    case artifactIntegrityFailed(path: String, issues: [ArtifactIntegrityIssue])
    case readFailed(String)
    case writeFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .projectRootIsNotAbsolute:
            return "Project root must be an absolute file URL."
        case .projectRootIsNotDirectory:
            return "Project root must identify a directory."
        case .invalidRelativePath(let path):
            return "Workspace path is not relative: \(path)"
        case .pathOutsideWorkspace(let path):
            return "Workspace path escapes the .xcircuite boundary: \(path)"
        case .invalidArtifactLocation(let location):
            return "Artifact location is invalid: \(location)"
        case .missingArtifact(let path):
            return "Workspace artifact does not exist: \(path)"
        case .artifactIntegrityFailed(let path, let issues):
            let codes = issues.map { $0.code.rawValue }.joined(separator: ", ")
            return "Workspace artifact integrity verification failed for \(path): \(codes)"
        case .readFailed(let message):
            return "Workspace read failed: \(message)"
        case .writeFailed(let message):
            return "Workspace write failed: \(message)"
        case .encodeFailed(let message):
            return "Workspace encoding failed: \(message)"
        case .decodeFailed(let message):
            return "Workspace decoding failed: \(message)"
        }
    }
}
