import Foundation
import XcircuitePackage

enum XcircuiteRunManifestTamperError: Error {
    case invalidManifestObject
    case invalidArtifactObject
    case invalidProjectObject
    case missingManifestProjection
}

enum XcircuiteRunManifestTamper {
    static func append(
        _ references: [XcircuiteFileReference],
        to manifestURL: URL
    ) throws {
        let manifestData = try Data(contentsOf: manifestURL)
        guard var manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw XcircuiteRunManifestTamperError.invalidManifestObject
        }
        var artifacts = manifest["artifacts"] as? [[String: Any]] ?? []
        let encoder = JSONEncoder()
        for reference in references {
            let referenceData = try encoder.encode(reference)
            guard let artifact = try JSONSerialization.jsonObject(with: referenceData) as? [String: Any] else {
                throw XcircuiteRunManifestTamperError.invalidArtifactObject
            }
            artifacts.append(artifact)
        }
        manifest["artifacts"] = artifacts
        let updatedData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: manifestURL, options: .atomic)
        try synchronizeProjection(for: manifestURL, manifestData: updatedData)
    }

    private static func synchronizeProjection(
        for manifestURL: URL,
        manifestData: Data
    ) throws {
        let runID = manifestURL.deletingLastPathComponent().lastPathComponent
        let projectRoot = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectManifestURL = projectRoot
            .appending(path: XcircuitePackage.directoryName)
            .appending(path: XcircuitePackage.manifestFileName)
        let projectData = try Data(contentsOf: projectManifestURL)
        guard var project = try JSONSerialization.jsonObject(with: projectData) as? [String: Any],
              var files = project["files"] as? [[String: Any]] else {
            throw XcircuiteRunManifestTamperError.invalidProjectObject
        }
        guard let projectionIndex = files.firstIndex(where: {
            $0["artifactID"] as? String == "run-manifest"
                && $0["producedByRunID"] as? String == runID
        }) else {
            throw XcircuiteRunManifestTamperError.missingManifestProjection
        }

        files[projectionIndex]["sha256"] = XcircuiteHasher().sha256(data: manifestData)
        files[projectionIndex]["byteCount"] = manifestData.count
        project["files"] = files
        let updatedProjectData = try JSONSerialization.data(
            withJSONObject: project,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedProjectData.write(to: projectManifestURL, options: .atomic)
    }
}
