import DesignFlowKernel
import Foundation

/// Concrete `.xcircuite` run-ledger persistence for DesignFlowKernel.
///
/// The store is intentionally an actor because ledger writes are ordered I/O.
/// Stage execution, transitions, approval, and resume policy remain owned by
/// DesignFlowKernel; this type only persists and recovers the typed ledger.
public actor XcircuiteRunLedgerStore: FlowRunLedgerPersisting {
    public static let ledgerFileName = "ledger.json"

    private let workspace: XcircuiteWorkspaceStore
    private let projectRoot: URL

    public init(projectRoot: URL) throws {
        self.projectRoot = projectRoot.standardizedFileURL
        self.workspace = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
    }

    public func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger {
        try validateProjectRoot(projectRoot)
        try validateRunID(runID)
        let relativePath = Self.relativePath(for: runID)
        do {
            return try await workspace.read(FlowRunLedger.self, fromJSON: relativePath)
        } catch XcircuiteWorkspaceStoreError.missingArtifact {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        } catch let error as XcircuiteWorkspaceStoreError {
            throw FlowRunLedgerPersistenceError.storageFailed(error.localizedDescription)
        } catch {
            throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
        }
    }

    public func saveRunLedger(_ ledger: FlowRunLedger, projectRoot: URL) async throws {
        try validateProjectRoot(projectRoot)
        try validateRunID(ledger.runID)
        do {
            try await workspace.write(ledger, asJSONTo: Self.relativePath(for: ledger.runID))
        } catch let error as XcircuiteWorkspaceStoreError {
            throw FlowRunLedgerPersistenceError.storageFailed(error.localizedDescription)
        } catch {
            throw FlowRunLedgerPersistenceError.encodingFailed(error.localizedDescription)
        }
    }

    public static func relativePath(for runID: String) -> String {
        "runs/\(runID)/\(ledgerFileName)"
    }

    private func validateRunID(_ runID: String) throws {
        guard !runID.isEmpty,
              !runID.contains("/"),
              !runID.contains("\\"),
              !runID.contains(".."),
              !runID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw FlowRunLedgerPersistenceError.storageFailed("Invalid run ID: \(runID)")
        }
    }

    private func validateProjectRoot(_ root: URL) throws {
        guard root.standardizedFileURL == projectRoot else {
            throw FlowRunLedgerPersistenceError.storageFailed(
                "Ledger project root does not match the store boundary."
            )
        }
    }
}
