import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    @discardableResult
    public func persistDesignDiff(_ diff: DesignDiff) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistArtifact(
            content: encoder.encode(diff),
            id: ArtifactID(rawValue: "design-diff"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(diff.runID)/design-diff.json"
                ),
                role: .output,
                kind: .designDiff,
                format: .json
            ),
            runID: diff.runID,
            mode: .replaceable
        )
    }

    public func loadDesignDiff(runID: String) async throws -> DesignDiff {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/design-diff.json"
            ),
            role: .output,
            kind: .designDiff,
            format: .json
        )
        guard let data = try await loadArtifactContent(at: locator) else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(locator.location.value)
        }
        return try JSONDecoder().decode(DesignDiff.self, from: data)
    }
}
