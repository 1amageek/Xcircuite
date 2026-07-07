import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct ProjectPathBoundary: Sendable {
    private enum ExplicitPathResolution {
        case resolved(String)
        case rejected
    }

    private enum SymbolicLinkResolution {
        case notSymbolicLink
        case destination(String)
        case unreadable
    }

    func relativePath(for url: URL, projectRoot: URL) throws -> String {
        guard let relativePath = relativePathIfContained(for: url, projectRoot: projectRoot) else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: normalizedPath(url.standardizedFileURL.path(percentEncoded: false)),
                projectRoot: normalizedPath(projectRoot.standardizedFileURL.path(percentEncoded: false))
            )
        }
        return relativePath
    }

    func relativePathIfContained(for url: URL, projectRoot: URL) -> String? {
        let roots = pathCandidates(for: projectRoot, treatAsDirectory: true)
        let files = pathCandidates(for: url, treatAsDirectory: false)
        guard !roots.isEmpty, !files.isEmpty else {
            return nil
        }
        guard files.allSatisfy({ filePath in roots.contains { rootPath in contains(filePath, in: rootPath) } }) else {
            return nil
        }
        for filePath in files {
            for rootPath in roots {
                if let relativePath = relativePath(for: filePath, rootPath: rootPath) {
                    return relativePath
                }
            }
        }
        return nil
    }

    func contains(_ url: URL, projectRoot: URL) -> Bool {
        relativePathIfContained(for: url, projectRoot: projectRoot) != nil
    }

    private func pathCandidates(for url: URL, treatAsDirectory: Bool) -> [String] {
        var candidates = [
            normalizedPath(url.standardizedFileURL.path(percentEncoded: false)),
            normalizedPath(url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)),
        ]
        switch explicitlyResolvedSymlinkPath(for: url) {
        case let .resolved(path):
            candidates.append(path)
        case .rejected:
            return []
        }
        return unique(candidates.map { path in
            treatAsDirectory ? normalizedDirectoryPath(path) : path
        })
    }

    private func explicitlyResolvedSymlinkPath(for url: URL) -> ExplicitPathResolution {
        let standardizedURL = url.standardizedFileURL
        let components = standardizedURL.pathComponents
        guard !components.isEmpty else {
            return .resolved(normalizedPath(standardizedURL.path(percentEncoded: false)))
        }

        var currentURL = components[0] == "/"
            ? URL(filePath: "/", directoryHint: .isDirectory)
            : URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)

        for component in components.dropFirst(components[0] == "/" ? 1 : 0) {
            let candidateURL = currentURL.appending(path: component)
            switch symbolicLinkResolution(at: candidateURL) {
            case let .destination(destination):
                currentURL = resolvedDestinationURL(destination, relativeTo: candidateURL)
            case .notSymbolicLink:
                currentURL = candidateURL
            case .unreadable:
                return .rejected
            }
        }
        return .resolved(normalizedPath(currentURL.standardizedFileURL.path(percentEncoded: false)))
    }

    private func symbolicLinkResolution(at url: URL) -> SymbolicLinkResolution {
        let path = url.path(percentEncoded: false)
        var fileStat = stat()
        guard path.withCString({ lstat($0, &fileStat) }) == 0 else {
            return .notSymbolicLink
        }
        guard (fileStat.st_mode & S_IFMT) == S_IFLNK else {
            return .notSymbolicLink
        }

        var capacity = Int(PATH_MAX)
        while capacity <= 1_048_576 {
            var buffer = [CChar](repeating: 0, count: capacity + 1)
            let length = path.withCString { pathPointer in
                buffer.withUnsafeMutableBufferPointer { bufferPointer in
                    readlink(pathPointer, bufferPointer.baseAddress, capacity)
                }
            }
            guard length >= 0 else {
                return .unreadable
            }
            guard length >= capacity else {
                let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
                return .destination(String(decoding: bytes, as: UTF8.self))
            }
            capacity *= 2
        }
        return .unreadable
    }

    private func resolvedDestinationURL(_ destination: String, relativeTo symlinkURL: URL) -> URL {
        let destinationURL: URL
        if destination.hasPrefix("/") {
            destinationURL = URL(filePath: destination)
        } else {
            destinationURL = symlinkURL
                .deletingLastPathComponent()
                .appending(path: destination)
        }
        return destinationURL.standardizedFileURL
    }

    private func relativePath(for filePath: String, rootPath: String) -> String? {
        guard contains(filePath, in: rootPath) else {
            return nil
        }
        if filePath == rootPath {
            return ""
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func contains(_ filePath: String, in rootPath: String) -> Bool {
        filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private func normalizedPath(_ path: String) -> String {
        normalizedDirectoryPath(path)
    }

    private func unique(_ paths: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for path in paths where !seen.contains(path) {
            seen.insert(path)
            result.append(path)
        }
        return result
    }
}
