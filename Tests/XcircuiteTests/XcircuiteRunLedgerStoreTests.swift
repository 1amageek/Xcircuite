import Foundation
import DesignFlowKernel
import Testing
@testable import Xcircuite

@Suite("XcircuiteRunLedgerStore")
struct XcircuiteRunLedgerStoreTests {
    @Test
    func rejectsUnsafeRunIDsBeforeTouchingDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteRunLedgerStore(projectRoot: root)
        await #expect(throws: FlowRunLedgerPersistenceError.storageFailed("Invalid run ID: ../escape")) {
            _ = try await store.loadRunLedger(runID: "../escape", projectRoot: root)
        }
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to clean up temporary workspace: \(error.localizedDescription)")
        }
    }
}
