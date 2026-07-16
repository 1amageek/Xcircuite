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
        let runDirectory = root
            .appending(path: XcircuiteWorkspaceLayout.directoryName)
            .appending(path: "runs")
            .appending(path: runID)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(
            to: runDirectory.appending(path: FlowRunProgressStore.cancellationRelativePath),
            options: [.atomic]
        )

        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: runDirectory,
            infrastructure: try XcircuiteWorkspaceStore(projectRoot: root),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let probe = FlowExecutionCancellationProbe.make(context: context)

        await #expect(throws: XcircuiteWorkspaceStoreError.self) {
            _ = try await probe()
        }
    }
}
