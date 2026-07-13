import DesignFlowKernel
import Foundation
import LogicDesign
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("LogicDesign flow stage adapters")
struct LogicDesignFlowStageExecutorTests {
    @Test("elaboration adapter persists canonical design and envelope artifacts")
    func elaborationPersistsArtifacts() async throws {
        let root = try makeRoot(name: "logic-elaboration-adapter")
        defer { removeRoot(root) }
        try Data("`define ADAPTER_VALUE 1".utf8)
            .write(to: root.appending(path: "defs.svh"), options: [.atomic])
        let sourceURL = root.appending(path: "top.sv")
        try Data("`include \"defs.svh\"\nmodule top(input logic a, output logic y); assign y = a & `ADAPTER_VALUE; endmodule".utf8)
            .write(to: sourceURL, options: [.atomic])
        let context = makeContext(root: root, runID: "logic-elaboration-adapter")

        let result = try await LogicElaborationFlowStageExecutor(
            sourceInput: .path(sourceURL.path),
            topDesignName: "top"
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.elaborate", displayName: "Logic elaboration"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.count == 3)
        #expect(result.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.artifacts.contains { $0.artifactID == "logic-design" })
        #expect(result.artifacts.allSatisfy {
            LocalArtifactVerifier().verify($0, relativeTo: root).isVerified
        })
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/logic.elaborate/raw/logic-design.json").path))
    }

    @Test("elaboration adapter persists a flattened hierarchy snapshot")
    func elaborationPersistsFlattenedHierarchy() async throws {
        let root = try makeRoot(name: "logic-hierarchy-elaboration-adapter")
        defer { removeRoot(root) }
        let sourceURL = root.appending(path: "top.sv")
        try Data("""
        module leaf(input logic a, output logic y);
            assign y = a;
        endmodule
        module top(input logic a, output logic y);
            leaf u_leaf(.a(a), .y(y));
        endmodule
        """.utf8).write(to: sourceURL, options: [.atomic])
        let context = makeContext(root: root, runID: "logic-hierarchy-elaboration-adapter")

        let result = try await LogicElaborationFlowStageExecutor(
            sourceInput: .path(sourceURL.path),
            topDesignName: "top"
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.elaborate", displayName: "Logic elaboration"),
            context: context
        )

        #expect(result.status == .succeeded)
        guard let snapshotArtifact = result.artifacts.first(where: { $0.artifactID == "logic-design" }) else {
            Issue.record("Expected the flattened logic-design artifact")
            return
        }
        let snapshotURL = try XcircuitePackage(projectRoot: root).url(
            forProjectRelativePath: snapshotArtifact.path
        )
        let snapshot = try LogicDesignSnapshotCodec.decode(try Data(contentsOf: snapshotURL))
        #expect(snapshot.rtl.modules.count == 1)
        #expect(snapshot.rtl.modules.first?.instances.isEmpty == true)
        #expect(snapshot.rtl.modules.first?.assignments.count == 2)
    }

    @Test("power-intent adapter preserves a completed result")
    func powerIntentPreservesResult() async throws {
        let root = try makeRoot(name: "logic-power-adapter")
        defer { removeRoot(root) }
        let sourceURL = root.appending(path: "power.upf")
        try Data("create_power_domain PD_A -elements {top}".utf8)
            .write(to: sourceURL, options: [.atomic])
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top", modules: [RTLModule(id: "m", name: "top")])
        ))
        let designURL = root.appending(path: "design.json")
        try LogicDesignSnapshotCodec.encode(snapshot).write(to: designURL, options: [.atomic])
        let context = makeContext(root: root, runID: "logic-power-adapter")

        let result = try await PowerIntentFlowStageExecutor(
            sourceInput: .path(sourceURL.path),
            designInput: .path(designURL.path),
            topDesignName: "top"
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.power-intent", displayName: "Power intent"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.count == 4)
        #expect(result.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.artifacts.allSatisfy {
            LocalArtifactVerifier().verify($0, relativeTo: root).isVerified
        })
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/logic.power-intent/raw/power-intent.json").path))
    }

    private func makeContext(root: URL, runID: String) -> FlowExecutionContext {
        let runDirectory = root
            .appending(path: XcircuitePackage.directoryName)
            .appending(path: "runs")
            .appending(path: runID)
        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        } catch {
            Issue.record("Failed to create run directory: \(error)")
        }
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: runDirectory,
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)")
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
}
