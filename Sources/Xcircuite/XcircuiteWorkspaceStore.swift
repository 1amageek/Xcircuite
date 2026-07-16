import Foundation
import CircuiteFoundation
import DesignFlowKernel

/// Concrete persistence boundary for the project-local `.xcircuite` directory.
///
/// The store owns filesystem access only. Flow lifecycle and run semantics remain
/// in DesignFlowKernel and are injected through its persistence protocols.
public actor XcircuiteWorkspaceStore {
    public let projectRoot: URL
    public let workspaceRoot: URL

    let pathBoundary = ProjectPathBoundary()
    let fileManager = FileManager.default

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
            try rejectSymbolicWorkspaceRoot()
        } catch {
            if let error = error as? XcircuiteWorkspaceStoreError {
                throw error
            }
            throw XcircuiteWorkspaceStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func url(for relativePath: String) throws -> URL {
        let workspaceRelativePath = try workspaceRelativePath(fromProjectRelativePath: relativePath)
        let url = try validatedWorkspaceURL(for: workspaceRelativePath)
        guard pathBoundary.contains(url, projectRoot: workspaceRoot) else {
            throw XcircuiteWorkspaceStoreError.pathOutsideWorkspace(relativePath)
        }
        return url
    }

    public func write(_ data: Data, to relativePath: String) throws {
        try write(data, to: relativePath, immutable: false)
    }

    /// Persists an immutable artifact.
    ///
    /// Repeating an identical write is idempotent. Replacing existing bytes is
    /// rejected so a retained run artifact can never be silently rewritten.
    public func writeImmutable(_ data: Data, to relativePath: String) throws {
        try write(data, to: relativePath, immutable: true)
    }

    private func write(_ data: Data, to relativePath: String, immutable: Bool) throws {
        try ensureWorkspace()
        let destination = try url(for: relativePath)
        let parent = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            _ = try url(for: relativePath)
            let lockURL = workspaceRoot.appending(path: ".workspace.lock")
            try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
                if immutable, fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                    guard existing == data else {
                        throw XcircuiteWorkspaceStoreError.immutableArtifactConflict(relativePath)
                    }
                    return
                }
                try data.write(to: destination, options: [.atomic])
            }
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
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

    /// Atomically validates and replaces mutable workspace state while holding
    /// the workspace's cross-process writer lock.
    func replace(
        _ data: Data,
        at relativePath: String,
        validatingCurrent validation: @Sendable (Data?) throws -> Void
    ) throws {
        try ensureWorkspace()
        let destination = try url(for: relativePath)
        let parent = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            _ = try url(for: relativePath)
            let lockURL = workspaceRoot.appending(path: ".workspace.lock")
            try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
                let current: Data?
                if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    current = try Data(contentsOf: destination, options: [.mappedIfSafe])
                } else {
                    current = nil
                }
                try validation(current)
                try data.write(to: destination, options: [.atomic])
            }
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw error
        }
    }

    /// Re-verifies a Foundation artifact reference against the project boundary.
    ///
    /// Both the recorded byte count and content digest are checked on every
    /// invocation. Artifact locations are constrained to the project boundary
    /// before verification so an absolute location or symlink cannot bypass
    /// project-local persistence.
    @discardableResult
    public func verify(_ reference: ArtifactReference) throws -> ArtifactIntegrity {
        let relativePath = try validatedArtifactPath(for: reference)
        let integrity = LocalArtifactVerifier().verify(
            reference,
            relativeTo: projectRoot
        )
        guard !integrity.issues.contains(where: { $0.code == .missingFile }) else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(relativePath)
        }
        guard integrity.isVerified else {
            throw XcircuiteWorkspaceStoreError.artifactIntegrityFailed(
                path: relativePath,
                issues: integrity.issues
            )
        }
        return integrity
    }

    /// Writes an encodable value as sorted-key JSON at a workspace-relative path.
    public func writeJSON<Value: Encodable & Sendable>(_ value: Value, to relativePath: String) throws {
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

    /// Reads and decodes a value from a workspace-relative JSON path.
    public func readJSON<Value: Decodable & Sendable>(_ type: Value.Type, from relativePath: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: read(from: relativePath))
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    public func writeWorkspaceText(_ text: String, to relativePath: String) throws {
        guard let data = text.data(using: .utf8) else {
            throw XcircuiteWorkspaceStoreError.encodeFailed("Text is not valid UTF-8.")
        }
        try write(data, to: relativePath)
    }

    public func ensureWorkspaceDirectory(at relativePath: String) throws {
        try ensureWorkspace()
        let directory = try url(for: relativePath)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try url(for: relativePath)
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.createDirectoryFailed(error.localizedDescription)
        }
    }

    public func workspaceFileExists(at relativePath: String) throws -> Bool {
        let url = try url(for: relativePath)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    public func workspaceItemExists(at relativePath: String) throws -> Bool {
        fileManager.fileExists(atPath: try url(for: relativePath).path(percentEncoded: false))
    }

    private func validatedWorkspaceURL(for relativePath: String) throws -> URL {
        try rejectSymbolicWorkspaceRoot()
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

    private func rejectSymbolicWorkspaceRoot() throws {
        guard fileManager.fileExists(atPath: workspaceRoot.path(percentEncoded: false)) else {
            return
        }
        do {
            let values = try workspaceRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw XcircuiteWorkspaceStoreError.symbolicWorkspaceRoot(
                    workspaceRoot.path(percentEncoded: false)
                )
            }
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.readFailed(error.localizedDescription)
        }
    }

    private func validatedArtifactPath(for reference: ArtifactReference) throws -> String {
        switch reference.locator.location.storage {
        case .workspaceRelative:
            let projectRelativePath = reference.locator.location.value
            _ = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
                .url(forProjectRelativePath: projectRelativePath)
            return projectRelativePath
        case .absoluteFileURL:
            let value = reference.locator.location.value
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(value)
        }
    }

    public func configurationURL(named fileName: String) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: projectRoot).configurationURL(named: fileName)
    }

    public func createWorkspace() throws {
        try ensureWorkspace()
        let manifestURL = XcircuiteWorkspaceLayout(projectRoot: projectRoot).manifestURL
        let lockURL = workspaceRoot.appending(path: ".project.lock")
        try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            if fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
                _ = try readJSON(
                    XcircuiteProjectManifest.self,
                    from: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)"
                )
                return
            }
            let displayName = projectRoot.lastPathComponent.isEmpty ? "Untitled" : projectRoot.lastPathComponent
            let manifest = XcircuiteProjectManifest.makeDefault(displayName: displayName)
            try writeJSON(
                manifest,
                to: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)"
            )
        }
    }

    public func isWorkspace() -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: workspaceRoot.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    public func loadManifest() throws -> XcircuiteProjectManifest {
        try readJSON(
            XcircuiteProjectManifest.self,
            from: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)"
        )
    }

    public func saveManifest(_ manifest: XcircuiteProjectManifest) throws {
        try manifest.validate()
        try writeJSON(
            manifest,
            to: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)"
        )
    }

    public func makeArtifactReference(
        forProjectRelativePath path: String,
        artifactID: String? = nil,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try XcircuiteWorkspaceLayout.validateProjectRelativePath(path)
        let projectRelativePath = path
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: projectRelativePath),
            role: role,
            kind: kind,
            format: format
        )
        let captured = try LocalArtifactReferencer().reference(
            locator,
            relativeTo: projectRoot
        )
        return ArtifactReference(
            id: try artifactID.map { try ArtifactID(rawValue: $0) },
            locator: captured.locator,
            digest: captured.digest,
            byteCount: captured.byteCount,
            producer: captured.producer
        )
    }

    public func makeArtifactReference(
        forProjectRelativePath path: String,
        artifactID: String? = nil,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try makeArtifactReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            role: .output,
            kind: kind,
            format: format
        )
    }

    public func writeJSON<Value: Encodable & Sendable>(
        _ value: Value,
        named fileName: String
    ) throws {
        try writeJSON(value, to: ".xcircuite/\(fileName)")
    }

    public func readJSON<Value: Decodable & Sendable>(
        _ type: Value.Type,
        named fileName: String
    ) throws -> Value {
        try readJSON(type, from: ".xcircuite/\(fileName)")
    }

    func workspaceRelativePath(fromProjectRelativePath path: String) throws -> String {
        let prefix = "\(XcircuiteWorkspaceLayout.directoryName)/"
        guard path.hasPrefix(prefix) else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(path)
        }
        let relativePath = String(path.dropFirst(prefix.count))
        _ = try validatedWorkspaceURL(for: relativePath)
        return relativePath
    }

    func rejectSymbolicWorkspaceRoot(_ root: URL) throws {
        guard fileManager.fileExists(atPath: root.path(percentEncoded: false)) else { return }
        let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw XcircuiteWorkspaceStoreError.symbolicWorkspaceRoot(root.path(percentEncoded: false))
        }
    }
}
