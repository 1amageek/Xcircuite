import Foundation
import Testing
import DesignFlowKernel
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("Flow execution cancellation probe")
struct FlowExecutionCancellationProbeTests {
    @Test func unreadableCancellationRequestPropagatesError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-cancel-probe-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary root: \(error)")
            }
        }

        let runID = "run-cancel-probe"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runDirectory = try await prepareTestRun(runID: runID, store: store)
        _ = try await store.persistCancellationRequest(
            FlowRunCancellationRequest(
                runID: runID,
                requestedBy: "test",
                reason: "Test corrupted cancellation projection."
            )
        )
        try Data("{".utf8).write(
            to: runDirectory.appending(path: FlowRunProgressStore.cancellationRelativePath),
            options: [.atomic]
        )

        let manifest = try await store.loadManifest()
        let context = FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let probe = FlowExecutionCancellationProbe.make(context: context)

        await #expect(throws: FlowRunLedgerPersistenceError.self) {
            _ = try await probe()
        }
    }
}
