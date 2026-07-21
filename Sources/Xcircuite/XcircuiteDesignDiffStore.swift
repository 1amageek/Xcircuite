import CircuiteFoundation
import DesignFlowKernel
import Foundation

extension XcircuiteWorkspaceStore {
    @discardableResult
    public func persistDesignDiff(_ diff: DesignDiff) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let content = try encoder.encode(diff)
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        return try persistRunArtifact(
            content: content,
            id: ArtifactID(rawValue: "design-diff"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(diff.runID)/design-diffs/\(digest.hexadecimalValue).json"
                ),
                role: .output,
                kind: .designDiff,
                format: .json
            ),
            runID: diff.runID,
            producer: nil,
            mode: .immutable,
            permitsRunControlPath: false,
            updatingLedger: { ledger in
                ledger.designDiff = diff
            }
        )
    }

    public func loadDesignDiff(runID: String) async throws -> DesignDiff {
        let ledger = try await loadRunLedger(runID: runID)
        guard let designDiff = ledger.designDiff else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(
                ".xcircuite/runs/\(runID)/design-diffs"
            )
        }
        return designDiff
    }
}
