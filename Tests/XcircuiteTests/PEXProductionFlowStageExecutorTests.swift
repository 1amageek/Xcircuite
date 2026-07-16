import DesignFlowKernel
import Foundation
import PEXEngine
import Testing
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("Production PEX flow stage executor")
struct PEXProductionFlowStageExecutorTests {
    @Test("production PEX blocks when the Magic executable is unavailable", .timeLimit(.minutes(1)))
    func productionPEXBlocksWithoutAnExecutable() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }

        try Data("layout".utf8).write(to: root.appending(path: "layout.gds"), options: .atomic)
        try Data(".subckt TESTCELL\n.ends TESTCELL\n".utf8)
            .write(to: root.appending(path: "source.spice"), options: .atomic)

        let executor = PEXFlowStageExecutor.production(
            stageID: "signoff.pex",
            layoutInput: .path("layout.gds"),
            layoutFormat: .gds,
            sourceNetlistInput: .path("source.spice"),
            topCell: "TESTCELL",
            corners: [PEXCorner(id: "tt")],
            technology: .inline(makeTechnology()),
            backendSelection: PEXBackendSelection(
                backendID: "magic",
                executablePath: root.appending(path: "missing-magic").path(percentEncoded: false)
            )
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "production-pex-readiness",
                intent: "Run production PEX only when the selected extractor is available.",
                stages: [
                    FlowStageDefinition(stageID: "signoff.pex", displayName: "Production PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )

        let stage = try #require(result.stages.first)
        #expect(executor.toolID == "pex-magic")
        #expect(result.status == .blocked, "Unexpected run result: \(result)")
        #expect(stage.status == .blocked, "Unexpected stage result: \(stage)")
        #expect(stage.diagnostics.contains { $0.code == "PEX_BACKEND_UNAVAILABLE" }, "Diagnostics: \(stage.diagnostics)")
        #expect(stage.gates.contains {
            $0.gateID == "pex" && $0.status == .blocked
        })
        #expect(!stage.artifacts.contains { $0.artifactID == "pex-summary" })
    }

    private func makeTechnology() -> TechnologyIR {
        TechnologyIR(
            processName: "production-pex-fixture",
            stack: [
                TechnologyLayer(
                    name: "M1",
                    order: 0,
                    thickness: 0.1,
                    material: "copper",
                    resistivity: 1.7e-8
                ),
            ],
            logicalToPhysicalLayerMap: [:],
            vias: [],
            defaultExtractionRules: .default,
            backendHints: [:]
        )
    }

    private func makeOrchestrator(root: URL) throws -> DefaultFlowOrchestrator {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        return DefaultFlowOrchestrator(
            infrastructure: store,
            ledgerPersistence: store,
            progressStore: FlowRunProgressStore(persistence: store)
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PEXProductionFlowStageExecutorTests-\(UUID().uuidString)")
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
