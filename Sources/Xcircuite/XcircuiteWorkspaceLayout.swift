import CircuiteFoundation
import DesignFlowKernel
import Foundation

/// Concrete layout of Xcircuite's project-local workspace.
public struct XcircuiteWorkspaceLayout: Sendable, Hashable {
    public static let directoryName = ".xcircuite"
    public static let manifestFileName = "project.json"

    public let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot.standardizedFileURL
    }

    public var workspaceURL: URL {
        projectRoot.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    public var manifestURL: URL {
        workspaceURL.appending(path: Self.manifestFileName)
    }

    public func configurationURL(named fileName: String) throws -> URL {
        guard !fileName.isEmpty,
              !fileName.hasPrefix("/"),
              !fileName.hasPrefix("~"),
              !fileName.contains("/"),
              fileName != ".",
              fileName != ".." else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(fileName)
        }
        return workspaceURL.appending(path: fileName)
    }

    public func runDirectoryURL(for runID: String) throws -> URL {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        return workspaceURL.appending(path: "runs").appending(path: runID)
    }

    public func url(forProjectRelativePath rawPath: String) throws -> URL {
        try Self.validateProjectRelativePath(rawPath)
        let destination = projectRoot.appending(path: rawPath).standardizedFileURL
        guard ProjectPathBoundary().contains(destination, projectRoot: projectRoot) else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(rawPath)
        }
        return destination
    }

    public static func validateProjectRelativePath(_ rawPath: String) throws {
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !rawPath.isEmpty,
              !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("~"),
              !rawPath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(rawPath)
        }
    }
}
