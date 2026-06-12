import DesignFlowKernel
import Foundation
import PEXEngine
import Testing
import ToolQualification
import Xcircuite

@Suite("PEX flow stage executor")
struct PEXFlowStageExecutorTests {
    @Test func mockPEXExecutorRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("pex-pass")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: ToolTrustRequirement(
                            kind: .pex,
                            operationID: "run-pex",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.gdsii, .spice],
                            requiredOutputFormats: [.spef, .json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.mockPEX()]),
            healthResults: [
                "mock-pex": ToolHealthCheckResult(toolID: "mock-pex", status: .passed),
            ],
            executors: [
                PEXFlowStageExecutor.mock(
                    stageID: "009-pex",
                    layoutURL: layoutURL,
                    layoutFormat: .gds,
                    sourceNetlistURL: netlistURL,
                    topCell: "TESTCELL",
                    corners: [PEXCorner(id: "tt")],
                    technology: .inline(makeTestTech())
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates.first?.gateID == "pex")
        #expect(result.stages[0].gates.first?.status == .passed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "PEX_WARNING" })
        #expect(artifacts.contains { $0.path.hasSuffix("manifest.json") })
        #expect(artifacts.contains { $0.format == .spef })
        #expect(artifacts.contains { $0.kind == .parasitic && $0.format == .json })
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
        #expect(artifacts.allSatisfy { $0.path.contains(".xcircuite/runs/run-pex/stages/009-pex/raw") })
    }

    @Test func pexExecutorForcesFlowManagedWorkingDirectory() async throws {
        let root = try makeTemporaryRoot("pex-forced-workdir")
        defer { removeTemporaryRoot(root) }
        let externalDirectory = try makeTemporaryRoot("external-pex-workdir")
        defer { removeTemporaryRoot(externalDirectory) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "mock-pex",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: .mock(),
                        options: .default,
                        workingDirectory: externalDirectory
                    ),
                    engine: DefaultPEXEngine.withDefaults()
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].artifacts.allSatisfy {
            $0.path.contains(".xcircuite/runs/run-pex/stages/009-pex/raw")
        })
        #expect(directoryIsEmpty(externalDirectory))
    }

    private func makeTestTech() -> TechnologyIR {
        TechnologyIR(
            processName: "test_process",
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

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PEXFlowStageExecutorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func directoryIsEmpty(_ directory: URL) -> Bool {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        } catch {
            Issue.record("Failed to inspect temporary root: \(error)")
            return false
        }
    }
}
