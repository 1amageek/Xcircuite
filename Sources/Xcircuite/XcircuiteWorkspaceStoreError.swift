import Foundation
import CircuiteFoundation

public enum XcircuiteWorkspaceStoreError: Error, Sendable, Equatable, LocalizedError {
    case projectRootIsNotAbsolute
    case projectRootIsNotDirectory
    case createDirectoryFailed(String)
    case invalidRelativePath(String)
    case pathOutsideWorkspace(String)
    case invalidArtifactLocation(String)
    case artifactOutsideRun(path: String, runID: String)
    case reservedRunControlPath(String)
    case terminalRunArtifactMutation(runID: String, path: String)
    case projectArtifactChanged(String)
    case missingArtifact(String)
    case artifactAlreadyExists(String)
    case immutableArtifactConflict(String)
    case appendOnlyArtifactConflict(String)
    case artifactIntegrityFailed(path: String, issues: [ArtifactIntegrityIssue])
    case symbolicWorkspaceRoot(String)
    case lockFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)
    case invalidProjectManifest(String)
    case invalidCancellationRequest(String)
    case runManifestCannotBeProjectFile(String)
    case unsafeProjectPath(String)

    public var errorDescription: String? {
        switch self {
        case .projectRootIsNotAbsolute:
            return "Project root must be an absolute file URL."
        case .projectRootIsNotDirectory:
            return "Project root must identify a directory."
        case .createDirectoryFailed(let message):
            return "Failed to create workspace directory: \(message)"
        case .invalidRelativePath(let path):
            return "Workspace path is not relative: \(path)"
        case .pathOutsideWorkspace(let path):
            return "Workspace path escapes the .xcircuite boundary: \(path)"
        case .invalidArtifactLocation(let location):
            return "Artifact location is invalid: \(location)"
        case .artifactOutsideRun(let path, let runID):
            return "Run artifact path \(path) does not belong to run \(runID)."
        case .reservedRunControlPath(let path):
            return "Stage artifact persistence cannot write the reserved run-control path: \(path)."
        case .terminalRunArtifactMutation(let runID, let path):
            return "Terminal run \(runID) cannot be mutated by artifact persistence at \(path)."
        case .projectArtifactChanged(let path):
            return "Project artifact changed before its audited mutation could be committed: \(path)"
        case .missingArtifact(let path):
            return "Workspace artifact does not exist: \(path)"
        case .artifactAlreadyExists(let path):
            return "Workspace artifact already exists: \(path)"
        case .immutableArtifactConflict(let path):
            return "Immutable workspace artifact already exists with different content: \(path)"
        case .appendOnlyArtifactConflict(let path):
            return "Append-only workspace artifact does not preserve the existing content at \(path)"
        case .artifactIntegrityFailed(let path, let issues):
            let codes = issues.map { $0.code.rawValue }.joined(separator: ", ")
            return "Workspace artifact integrity verification failed for \(path): \(codes)"
        case .symbolicWorkspaceRoot(let path):
            return "The .xcircuite workspace root must not be a symbolic link: \(path)"
        case .lockFailed(let message):
            return "Workspace lock failed: \(message)"
        case .readFailed(let message):
            return "Workspace read failed: \(message)"
        case .writeFailed(let message):
            return "Workspace write failed: \(message)"
        case .encodeFailed(let message):
            return "Workspace encoding failed: \(message)"
        case .decodeFailed(let message):
            return "Workspace decoding failed: \(message)"
        case .invalidProjectManifest(let reason):
            return "Invalid project manifest: \(reason)"
        case .invalidCancellationRequest(let reason):
            return "Invalid run cancellation request: \(reason)"
        case .runManifestCannotBeProjectFile(let path):
            return "Run manifest cannot be registered as a project file: \(path)"
        case .unsafeProjectPath(let path):
            return "Unsafe project path: \(path)"
        }
    }
}
