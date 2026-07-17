import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicIR
import PDKCore
import PhysicalDesignCore
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("Physical design flow stage adapter")
struct PhysicalDesignFlowStageExecutorTests {
    @Test("floorplan adapter executes a native request and verifies immutable artifacts")
    func floorplanAdapterExecutes() async throws {
        let root = try makeRoot(name: "physical-design-adapter")
        defer { removeRoot(root) }
        let runID = "physical-design-adapter"
        let request = PhysicalDesignRequest(
            runID: runID,
            inputs: [],
            design: LogicDesignReference(
                artifact: try fixtureReference(path: "inputs/design.json", kind: .netlist, format: .json),
                topDesignName: "adapter_top",
                designDigest: String(repeating: "b", count: 64)
            ),
            constraints: try fixtureReference(path: "inputs/constraints.sdc", kind: .constraint, format: .sdc),
            requestedModeIDs: ["func"],
            pdk: PDKReference(
                manifest: try fixtureReference(path: "inputs/pdk.json", kind: .technology, format: .json),
                processID: "fixture-130nm",
                version: "1",
                digest: String(repeating: "c", count: 64)
            ),
            stage: .floorplan,
            initialSnapshot: PhysicalDesignSnapshot(
                topCell: "adapter_top",
                cells: [PhysicalDesignSnapshot.Cell(id: "U1", master: "BUF_X1")]
            )
        )
        let requestURL = root.appending(path: "request.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(request).write(to: requestURL, options: [.atomic])
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        _ = try await prepareTestRun(runID: runID, store: workspaceStore)
        let manifest = try await workspaceStore.loadManifest()
        let context = FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )

        let result = try await PhysicalDesignFlowStageExecutor.local(
            stageID: "physical.floorplan",
            requestInput: .path(requestURL.path)
        ).execute(
            stage: FlowStageDefinition(stageID: "physical.floorplan", displayName: "Floorplan"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.count == 4)
        #expect(result.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.artifacts.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0.path).path) })
    }

    @Test("adapter blocks a request sent to the wrong physical stage")
    func stageMismatchIsBlocked() async throws {
        let root = try makeRoot(name: "physical-design-stage-mismatch")
        defer { removeRoot(root) }
        let runID = "physical-design-stage-mismatch"
        let request = PhysicalDesignRequest(
            runID: runID,
            inputs: [],
            design: LogicDesignReference(
                artifact: try fixtureReference(path: "inputs/design.json", kind: .netlist, format: .json),
                topDesignName: "adapter_top",
                designDigest: String(repeating: "b", count: 64)
            ),
            constraints: try fixtureReference(path: "inputs/constraints.sdc", kind: .constraint, format: .sdc),
            requestedModeIDs: ["func"],
            pdk: PDKReference(
                manifest: try fixtureReference(path: "inputs/pdk.json", kind: .technology, format: .json),
                processID: "fixture-130nm",
                version: "1",
                digest: String(repeating: "c", count: 64)
            ),
            stage: .placement,
            initialSnapshot: PhysicalDesignSnapshot(topCell: "adapter_top")
        )
        let requestURL = root.appending(path: "request.json")
        try JSONEncoder().encode(request).write(to: requestURL, options: [.atomic])
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        _ = try await prepareTestRun(runID: runID, store: workspaceStore)
        let manifest = try await workspaceStore.loadManifest()
        let context = FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )

        let result = try await PhysicalDesignFlowStageExecutor.local(
            stageID: "physical.floorplan",
            requestInput: .path(requestURL.path)
        ).execute(
            stage: FlowStageDefinition(stageID: "physical.floorplan", displayName: "Floorplan"),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "PHYSICAL_DESIGN_STAGE_MISMATCH" })
    }

    @Test("physical review persists a packet and resumes through the flow approval gate")
    func physicalReviewApprovalResumesFlow() async throws {
        let root = try makeRoot(name: "physical-design-review-resume")
        defer { removeRoot(root) }
        let runID = "physical-design-review-resume"
        let request = PhysicalDesignRequest(
            runID: runID,
            inputs: [],
            design: LogicDesignReference(
                artifact: try fixtureReference(path: "inputs/design.json", kind: .netlist, format: .json),
                topDesignName: "review_top",
                designDigest: String(repeating: "b", count: 64)
            ),
            constraints: try fixtureReference(path: "inputs/constraints.sdc", kind: .constraint, format: .sdc),
            requestedModeIDs: ["func"],
            pdk: PDKReference(
                manifest: try fixtureReference(path: "inputs/pdk.json", kind: .technology, format: .json),
                processID: "fixture-130nm",
                version: "1",
                digest: String(repeating: "c", count: 64)
            ),
            stage: .floorplan,
            initialSnapshot: PhysicalDesignSnapshot(
                topCell: "review_top",
                cells: [PhysicalDesignSnapshot.Cell(id: "U1", master: "BUF_X1")]
            )
        )
        let requestURL = root.appending(path: "request.json")
        try JSONEncoder().encode(request).write(to: requestURL, options: [.atomic])
        let manifestPath = "runs/\(runID)/physical-design/floorplan/run-manifest.json"
        let executors: [any FlowStageExecutor] = [
            PhysicalDesignFlowStageExecutor.local(
                stageID: "physical.floorplan",
                requestInput: .path(requestURL.path)
            ),
            PhysicalDesignReviewFlowStageExecutor(
                manifestInput: .path(manifestPath)
            )
        ]
        let stages = [
            FlowStageDefinition(stageID: "physical.floorplan", displayName: "Floorplan"),
            FlowStageDefinition(
                stageID: "physical.review",
                displayName: "Physical Design Review",
                requiresApproval: true
            )
        ]
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        let manifest = try await workspaceStore.loadManifest()
        let workspaceID = try FlowWorkspaceID(rawValue: manifest.identity.projectID)
        let operation = FlowOperationRequest(
            workspaceID: workspaceID,
            runID: runID,
            intent: "Run physical design and obtain human review.",
            stages: stages
        )
        let orchestrator = DefaultFlowOrchestrator(
            infrastructure: workspaceStore,
            ledgerPersistence: workspaceStore,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "XcircuiteTests",
                version: "1.0.0"
            ),
            progressStore: FlowRunProgressStore(persistence: workspaceStore)
        )
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        let ledgerInspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)
        let initial = try await orchestrator.run(
            request: operation,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(
            initial.status == .blocked,
            "Unexpected physical review run result: \(initial.stages)"
        )
        #expect(initial.stages.last?.artifacts.contains { $0.artifactID == "physical-design-review-packet" } == true)
        #expect(initial.stages.last?.gates.contains { $0.gateID == "approval" && $0.status == .incomplete } == true)

        _ = try await DefaultFlowGateApprovalRecorder(
            loader: workspaceStore,
            inspector: ledgerInspector,
            ledgerPersistence: workspaceStore
        ).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: workspaceID,
                runID: runID,
                stageID: "physical.review",
                verdict: .approved,
                reviewer: "human-reviewer",
                note: "Reviewed immutable layout revision and design diff."
            )
        )
        let resumed = try await DefaultFlowRunResumer(
            loader: workspaceStore,
            orchestrator: orchestrator,
            inspector: ledgerInspector,
            artifactPersistence: workspaceStore
        ).resumeRun(
            request: FlowRunResumeRequest(workspaceID: workspaceID, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.result.status == .succeeded)
        #expect(resumed.result.stages.last?.gates.contains { $0.gateID == "approval" && $0.status == .passed } == true)
        #expect(resumed.summary.approvalCount == 1)
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func fixtureLocator(
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactLocator {
        try ArtifactLocator(
            location: ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: kind,
            format: format
        )
    }

    private func fixtureReference(
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try ArtifactReference(
            locator: fixtureLocator(path: path, kind: kind, format: format),
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: 0
        )
    }
}
