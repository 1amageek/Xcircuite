import DesignFlowKernel
import DRCEngine
import Foundation
import LVSEngine
import Testing
import ToolQualification
import Xcircuite
import XcircuitePackage

@Suite("Signoff flow stage executors")
struct SignoffFlowStageExecutorTests {
    @Test func pureSwiftDRCExecutorRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("drc-pass")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeLayout(
            PureSwiftDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    PureSwiftDRCRectangle(id: "m1_a", layer: "met1", xMin: 0, yMin: 0, xMax: 1, yMax: 1),
                    PureSwiftDRCRectangle(id: "m1_b", layer: "met1", xMin: 2, yMin: 0, xMax: 3, yMax: 1),
                ],
                rules: [
                    PureSwiftDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                    PureSwiftDRCRule(id: "met1.space", kind: .minimumSpacing, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: ToolTrustRequirement(
                            kind: .drc,
                            operationID: "run-drc",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.json],
                            requiredOutputFormats: [.json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.pureSwiftDRC()]),
            healthResults: [
                "pure-swift-drc": ToolHealthCheckResult(toolID: "pure-swift-drc", status: .passed),
            ],
            executors: [
                DRCFlowStageExecutor.pureSwift(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates == [FlowGateResult(gateID: "drc", status: .passed)])
        #expect(result.stages[0].artifacts.contains { $0.path.contains("drc-report") })
    }

    @Test func drcExecutorForcesFlowManagedWorkingDirectory() async throws {
        let root = try makeTemporaryRoot("drc-forced-workdir")
        defer { removeTemporaryRoot(root) }
        let externalDirectory = try makeTemporaryRoot("external-drc-workdir")
        defer { removeTemporaryRoot(externalDirectory) }

        let layoutURL = try writeLayout(
            PureSwiftDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    PureSwiftDRCRectangle(id: "m1_a", layer: "met1", xMin: 0, yMin: 0, xMax: 1, yMax: 1),
                ],
                rules: [
                    PureSwiftDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "pure-swift-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        workingDirectory: externalDirectory,
                        backendSelection: DRCBackendSelection(backendID: "pure-swift")
                    ),
                    engine: DefaultDRCEngine(backend: nil)
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(artifacts.contains { $0.path.contains(".xcircuite/runs/run-drc/stages/007-drc/raw") })
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
        #expect(!directoryContainsReport(externalDirectory))
    }

    @Test func pureSwiftDRCExecutorFailsGateOnViolation() async throws {
        let root = try makeTemporaryRoot("drc-fail")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeLayout(
            PureSwiftDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    PureSwiftDRCRectangle(id: "thin", layer: "met1", xMin: 0, yMin: 0, xMax: 0.1, yMax: 1),
                ],
                rules: [
                    PureSwiftDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor.pureSwift(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .failed)
        #expect(result.stages[0].gates.first?.status == .failed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "met1.width" })
    }

    @Test func pureSwiftLVSExecutorRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("lvs-pass")
        defer { removeTemporaryRoot(root) }

        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let layoutURL = try writeNetlist(matchingNetlist(), name: "layout.spice", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: ToolTrustRequirement(
                            kind: .lvs,
                            operationID: "run-lvs",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.spice],
                            requiredOutputFormats: [.json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.pureSwiftLVS()]),
            healthResults: [
                "pure-swift-lvs": ToolHealthCheckResult(toolID: "pure-swift-lvs", status: .passed),
            ],
            executors: [
                LVSFlowStageExecutor.pureSwift(
                    stageID: "008-lvs",
                    layoutNetlistURL: layoutURL,
                    schematicNetlistURL: schematicURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates == [FlowGateResult(gateID: "lvs", status: .passed)])
        #expect(result.stages[0].artifacts.contains { $0.path.contains("lvs-report") })
    }

    private func matchingNetlist() -> String {
        """
        .subckt TOP in out vdd vss
        M1 out in vdd vdd pmos
        M2 out in vss vss nmos
        .ends TOP
        """
    }

    private func writeLayout(_ layout: PureSwiftDRCLayout, root: URL) throws -> URL {
        let url = root.appending(path: "layout.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func writeNetlist(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffFlowStageExecutorTests-\(name)-\(UUID().uuidString)")
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

    private func directoryContainsReport(_ directory: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            return contents.contains { $0.lastPathComponent.contains("drc-report") }
        } catch {
            Issue.record("Failed to inspect temporary root: \(error)")
            return false
        }
    }
}
