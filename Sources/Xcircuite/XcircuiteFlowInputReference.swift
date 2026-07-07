import DesignFlowKernel
import Foundation
import XcircuitePackage

public enum XcircuiteFlowInputReference: Sendable, Hashable, Codable {
    case path(String)
    case stageArtifact(StageArtifact)
    case stageRawArtifact(StageRawArtifact)

    public struct StageArtifact: Sendable, Hashable, Codable {
        public var stageID: String
        public var artifactID: String?
        public var kind: XcircuiteFileKind?
        public var format: XcircuiteFileFormat?
        public var pathSuffix: String?

        public init(
            stageID: String,
            artifactID: String? = nil,
            kind: XcircuiteFileKind? = nil,
            format: XcircuiteFileFormat? = nil,
            pathSuffix: String? = nil
        ) {
            self.stageID = stageID
            self.artifactID = artifactID
            self.kind = kind
            self.format = format
            self.pathSuffix = pathSuffix
        }
    }

    public struct StageRawArtifact: Sendable, Hashable, Codable {
        public var stageID: String
        public var relativePath: String

        public init(stageID: String, relativePath: String) {
            self.stageID = stageID
            self.relativePath = relativePath
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case path
        case stageArtifact
        case stageRawArtifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .path:
            self = .path(try container.decode(String.self, forKey: .value))
        case .stageArtifact:
            self = .stageArtifact(try container.decode(StageArtifact.self, forKey: .value))
        case .stageRawArtifact:
            self = .stageRawArtifact(try container.decode(StageRawArtifact.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .path(let path):
            try container.encode(Kind.path, forKey: .kind)
            try container.encode(path, forKey: .value)
        case .stageArtifact(let artifact):
            try container.encode(Kind.stageArtifact, forKey: .kind)
            try container.encode(artifact, forKey: .value)
        case .stageRawArtifact(let artifact):
            try container.encode(Kind.stageRawArtifact, forKey: .kind)
            try container.encode(artifact, forKey: .value)
        }
    }

    func resolve(projectRoot: URL, runDirectory: URL) throws -> URL {
        switch self {
        case .path(let path):
            return try XcircuiteFlowRuntimeSpec.resolvePath(path, projectRoot: projectRoot)
        case .stageArtifact(let artifact):
            return try resolveStageArtifact(artifact, projectRoot: projectRoot, runDirectory: runDirectory)
        case .stageRawArtifact(let artifact):
            try XcircuiteIdentifierValidator().validate(artifact.stageID, kind: .stageID)
            let components = try Self.validatedRelativePathComponents(artifact.relativePath)
            var url = Self.stageRawDirectory(runDirectory: runDirectory, stageID: artifact.stageID)
            for component in components {
                url = url.appending(path: component)
            }
            return url
        }
    }

    func resolveExisting(projectRoot: URL, runDirectory: URL) throws -> URL {
        let url = try resolve(projectRoot: projectRoot, runDirectory: runDirectory)
        if case .stageRawArtifact(let artifact) = self {
            return try Self.validateExistingFile(
                url,
                containedBy: [
                    runDirectory,
                    Self.stageRawDirectory(runDirectory: runDirectory, stageID: artifact.stageID),
                ],
                missingPath: url.path(percentEncoded: false),
                invalidReference: artifact.relativePath
            )
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw XcircuiteRuntimeError.inputReferenceMissing(url.path(percentEncoded: false))
        }
        return url
    }

    private static func validatedRelativePathComponents(_ path: String) throws -> [String] {
        guard !path.isEmpty else {
            throw XcircuiteRuntimeError.invalidInputReference(path)
        }
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else {
            throw XcircuiteRuntimeError.invalidInputReference(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: { $0.isEmpty || $0 == ".." }) else {
            throw XcircuiteRuntimeError.invalidInputReference(path)
        }
        return components
    }

    private func resolveStageArtifact(
        _ selector: StageArtifact,
        projectRoot: URL,
        runDirectory: URL
    ) throws -> URL {
        try XcircuiteIdentifierValidator().validate(selector.stageID, kind: .stageID)
        if let artifactID = selector.artifactID {
            try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
        }
        let pathSuffixComponents = try selector.pathSuffix.map(Self.validatedRelativePathComponents)
        let stageDirectory = Self.stageDirectory(runDirectory: runDirectory, stageID: selector.stageID)
        let resultURL = stageDirectory.appending(path: "result.json")
        let trustedResultURL = try Self.validateExistingFile(
            resultURL,
            containedBy: [
                runDirectory,
                stageDirectory,
            ],
            missingPath: resultURL.path(percentEncoded: false),
            invalidReference: "stage result \(selector.stageID)"
        )
        let resultData = try Data(contentsOf: trustedResultURL)
        let result = try JSONDecoder().decode(FlowStageResult.self, from: resultData)
        let matches = result.artifacts.filter { artifact in
            if let artifactID = selector.artifactID, artifact.artifactID != artifactID {
                return false
            }
            if let kind = selector.kind, artifact.kind != kind {
                return false
            }
            if let format = selector.format, artifact.format != format {
                return false
            }
            if let pathSuffixComponents,
               !Self.path(artifact.path, endsWithPathComponents: pathSuffixComponents) {
                return false
            }
            return true
        }
        guard let reference = matches.first else {
            throw XcircuiteRuntimeError.artifactReferenceNotFound(stageID: selector.stageID)
        }
        guard matches.count == 1 else {
            throw XcircuiteRuntimeError.artifactReferenceAmbiguous(
                stageID: selector.stageID,
                matchCount: matches.count
            )
        }
        let verifier = XcircuiteFileReferenceVerifier()
        let integrity = verifier.verify(reference, projectRoot: projectRoot)
        switch integrity.status {
        case .verified:
            guard let url = verifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
                throw XcircuiteRuntimeError.invalidInputReference(integrity.message)
            }
            return url
        case .missingArtifact:
            throw XcircuiteRuntimeError.inputReferenceMissing(reference.path)
        case .missingDigest:
            throw XcircuiteRuntimeError.artifactReferenceMissingDigest(path: reference.path)
        case .missingByteCount:
            throw XcircuiteRuntimeError.artifactReferenceMissingByteCount(path: reference.path)
        case .byteCountMismatch:
            guard let expectedByteCount = integrity.expectedByteCount,
                  let actualByteCount = integrity.actualByteCount else {
                throw XcircuiteRuntimeError.invalidInputReference(integrity.message)
            }
            throw XcircuiteRuntimeError.artifactReferenceByteCountMismatch(
                path: reference.path,
                expected: expectedByteCount,
                actual: actualByteCount
            )
        case .sha256Mismatch:
            guard let expectedSHA256 = integrity.expectedSHA256,
                  let actualSHA256 = integrity.actualSHA256 else {
                throw XcircuiteRuntimeError.invalidInputReference(integrity.message)
            }
            throw XcircuiteRuntimeError.artifactReferenceDigestMismatch(
                path: reference.path,
                expected: expectedSHA256,
                actual: actualSHA256
            )
        case .invalidPath, .invalidDigest, .invalidByteCount, .unreadableArtifact:
            throw XcircuiteRuntimeError.invalidInputReference(integrity.message)
        }
    }

    private static func stageDirectory(runDirectory: URL, stageID: String) -> URL {
        runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
    }

    private static func stageRawDirectory(runDirectory: URL, stageID: String) -> URL {
        stageDirectory(runDirectory: runDirectory, stageID: stageID)
            .appending(path: "raw")
    }

    private static func path(_ path: String, endsWithPathComponents suffixComponents: [String]) -> Bool {
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard pathComponents.count >= suffixComponents.count else {
            return false
        }
        return Array(pathComponents.suffix(suffixComponents.count)) == suffixComponents
    }

    private static func validateExistingFile(
        _ url: URL,
        containedBy roots: [URL],
        missingPath: String,
        invalidReference: String
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw XcircuiteRuntimeError.inputReferenceMissing(missingPath)
        }
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        for root in roots {
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            guard Self.normalizedPath(resolvedURL, isContainedBy: resolvedRoot) else {
                throw XcircuiteRuntimeError.invalidInputReference(invalidReference)
            }
        }
        return resolvedURL
    }

    private static func normalizedPath(_ url: URL, isContainedBy root: URL) -> Bool {
        let path = normalizedPath(url)
        let rootPath = normalizedPath(root)
        return path == rootPath || path.hasPrefix("\(rootPath)/")
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
