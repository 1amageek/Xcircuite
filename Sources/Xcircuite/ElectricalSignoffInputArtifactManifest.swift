import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct ElectricalSignoffInputArtifactManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var stageID: String
    public var inputArtifacts: [XcircuiteFileReference]
    public var manifestDigest: String

    public init(
        runID: String,
        stageID: String,
        inputArtifacts: [XcircuiteFileReference],
        manifestDigest: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.stageID = stageID
        self.inputArtifacts = inputArtifacts.sorted { $0.path < $1.path }
        self.manifestDigest = manifestDigest ?? Self.digest(
            runID: runID,
            stageID: stageID,
            inputArtifacts: self.inputArtifacts
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffInputArtifactManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !stageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffInputArtifactManifestError.invalidIdentity
        }
        guard !inputArtifacts.isEmpty else {
            throw ElectricalSignoffInputArtifactManifestError.emptyInputArtifacts
        }
        var paths = Set<String>()
        for artifact in inputArtifacts {
            guard paths.insert(artifact.path).inserted else {
                throw ElectricalSignoffInputArtifactManifestError.duplicatePath(artifact.path)
            }
            guard artifact.sha256 != nil, artifact.byteCount != nil else {
                throw ElectricalSignoffInputArtifactManifestError.missingIntegrity(artifact.path)
            }
        }
        let expectedDigest = Self.digest(
            runID: runID,
            stageID: stageID,
            inputArtifacts: inputArtifacts
        )
        guard expectedDigest == manifestDigest else {
            throw ElectricalSignoffInputArtifactManifestError.digestMismatch(
                expected: expectedDigest,
                actual: manifestDigest
            )
        }
    }

    public static func digest(
        runID: String,
        stageID: String,
        inputArtifacts: [XcircuiteFileReference]
    ) -> String {
        let canonical = ("runID=\(runID)\nstageID=\(stageID)" + inputArtifacts
            .sorted { $0.path < $1.path }
            .map { artifact in
                [
                    artifact.artifactID ?? "",
                    artifact.path,
                    artifact.kind.rawValue,
                    artifact.format.rawValue,
                    artifact.sha256 ?? "",
                    artifact.byteCount.map(String.init) ?? "",
                    artifact.producedByRunID ?? "",
                    artifact.verifiedByRunID ?? "",
                ].joined(separator: "|")
            }
            .joined(separator: "\n"))
        do {
            return try SHA256ContentDigester().digest(data: Data(canonical.utf8)).hexadecimalValue
        } catch {
            return ""
        }
    }
}
