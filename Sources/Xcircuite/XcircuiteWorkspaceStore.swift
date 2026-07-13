import Foundation

/// Concrete persistence boundary for the project-local `.xcircuite` directory.
///
/// The store owns filesystem access only. Flow lifecycle and run semantics remain
/// in DesignFlowKernel and are injected through its persistence protocols.
public actor XcircuiteWorkspaceStore {
    public let projectRoot: URL
    public let workspaceRoot: URL

    private let pathBoundary = ProjectPathBoundary()
    private let fileManager = FileManager.default

    public init(projectRoot: URL) throws {
        guard projectRoot.isFileURL, projectRoot.path(percentEncoded: false).hasPrefix("/") else {
            throw XcircuiteWorkspaceStoreError.projectRootIsNotAbsolute
        }

        let normalizedRoot = projectRoot.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: normalizedRoot.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue {
            throw XcircuiteWorkspaceStoreError.projectRootIsNotDirectory
        }

        self.projectRoot = normalizedRoot
        self.workspaceRoot = normalizedRoot.appending(path: ".xcircuite", directoryHint: .isDirectory)
    }

    public func ensureWorkspace() throws {
        do {
            try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        } catch {
            throw XcircuiteWorkspaceStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func url(for relativePath: String) throws -> URL {
        let url = try validatedURL(for: relativePath)
        guard pathBoundary.contains(url, projectRoot: workspaceRoot) else {
            throw XcircuiteWorkspaceStoreError.pathOutsideWorkspace(relativePath)
        }
        return url
    }

    public func write(_ data: Data, to relativePath: String) throws {
        let destination = try url(for: relativePath)
        let parent = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: destination, options: [.atomic])
        } catch {
            throw XcircuiteWorkspaceStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func read(from relativePath: String) throws -> Data {
        let source = try url(for: relativePath)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(relativePath)
        }
        do {
            return try Data(contentsOf: source, options: [.mappedIfSafe])
        } catch {
            throw XcircuiteWorkspaceStoreError.readFailed(error.localizedDescription)
        }
    }

    public func write<Value: Encodable & Sendable>(_ value: Value, asJSONTo relativePath: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            try write(encoder.encode(value), to: relativePath)
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.encodeFailed(error.localizedDescription)
        }
    }

    public func read<Value: Decodable & Sendable>(_ type: Value.Type, fromJSON relativePath: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: read(from: relativePath))
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\") else {
            throw XcircuiteWorkspaceStoreError.invalidRelativePath(relativePath)
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else {
            throw XcircuiteWorkspaceStoreError.invalidRelativePath(relativePath)
        }
        return workspaceRoot.appending(path: components.joined(separator: "/"))
    }
}
