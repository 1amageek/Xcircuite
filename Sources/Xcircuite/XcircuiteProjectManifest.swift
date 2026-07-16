import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct XcircuiteProjectManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public internal(set) var identity: FlowProjectIdentity
    public internal(set) var files: [ArtifactReference]
    public internal(set) var runs: [FlowRunReference]

    init(
        identity: FlowProjectIdentity,
        files: [ArtifactReference] = [],
        runs: [FlowRunReference] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.identity = identity
        self.files = files
        self.runs = runs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case identity
        case files
        case runs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected project manifest schema version \(Self.currentSchemaVersion)."
            )
        }
        identity = try container.decode(FlowProjectIdentity.self, forKey: .identity)
        files = try container.decode([ArtifactReference].self, forKey: .files)
        runs = try container.decode([FlowRunReference].self, forKey: .runs)

        do {
            try validate()
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: error.localizedDescription,
                    underlyingError: error
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(identity, forKey: .identity)
        try container.encode(files, forKey: .files)
        try container.encode(runs, forKey: .runs)
    }

    static func makeDefault(
        displayName: String,
        topDesignName: String = "TOP",
        projectID: String = UUID().uuidString
    ) -> XcircuiteProjectManifest {
        XcircuiteProjectManifest(
            identity: FlowProjectIdentity(
                projectID: projectID,
                displayName: displayName,
                topDesignName: topDesignName
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                "schemaVersion must be \(Self.currentSchemaVersion)."
            )
        }

        try FlowIdentifierValidator().validate(identity.projectID, kind: .projectID)
        guard !identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest("identity.displayName must not be empty.")
        }
        guard !identity.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest("identity.topDesignName must not be empty.")
        }

        var runIDs: Set<String> = []
        var runManifestPaths: Set<String> = []
        for reference in runs {
            try FlowIdentifierValidator().validate(reference.runID, kind: .runID)
            let expectedPath = Self.runManifestPath(for: reference.runID)
            guard reference.manifestPath == expectedPath else {
                throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                    "run '\(reference.runID)' must reference '\(expectedPath)'."
                )
            }
            guard runIDs.insert(reference.runID).inserted else {
                throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                    "runID '\(reference.runID)' must be unique."
                )
            }
            guard runManifestPaths.insert(reference.manifestPath).inserted else {
                throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                    "run manifest path '\(reference.manifestPath)' must be unique."
                )
            }
        }
        guard runs == runs.sorted(by: { $0.runID < $1.runID }) else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest("runs must be sorted by runID.")
        }

        var filePaths: Set<String> = []
        for reference in files {
            try XcircuiteWorkspaceLayout.validateProjectRelativePath(reference.path)
            guard filePaths.insert(reference.path).inserted else {
                throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                    "file path '\(reference.path)' must be unique."
                )
            }
            try FlowIdentifierValidator().validate(reference.artifactID, kind: .artifactID)
            try validateRunManifestProjection(reference, registeredRunIDs: runIDs)
        }
        guard files == files.sorted(by: { $0.path < $1.path }) else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest("files must be sorted by path.")
        }
    }

    private func validateRunManifestProjection(
        _ reference: ArtifactReference,
        registeredRunIDs: Set<String>
    ) throws {
        let components = reference.path.split(separator: "/", omittingEmptySubsequences: false)
        let pathRunID = components.count == 4
            && components[0] == Substring(XcircuiteWorkspaceLayout.directoryName)
            && components[1] == "runs"
            && components[3] == "manifest.json"
            ? String(components[2])
            : nil
        let isProjection = reference.artifactID == "run-manifest"

        guard isProjection || pathRunID == nil else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                "canonical run manifest '\(reference.path)' must use artifactID 'run-manifest'."
            )
        }
        guard isProjection else {
            return
        }
        guard let pathRunID,
              registeredRunIDs.contains(pathRunID),
              reference.kind == .other,
              reference.format == .json else {
            throw XcircuiteWorkspaceStoreError.invalidProjectManifest(
                "run manifest projection '\(reference.path)' must identify a registered canonical manifest with integrity metadata."
            )
        }
    }

    private static func runManifestPath(for runID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/manifest.json"
    }
}
