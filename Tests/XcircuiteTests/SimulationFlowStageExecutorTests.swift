import DesignFlowKernel
import Foundation
import Testing
import ToolQualification
import Xcircuite

/// Simulation as a flow stage at DRC/LVS/PEX maturity: the netlist's
/// own analysis runs in-process, the gate judges declared measurement
/// expectations, and waveform + measurements are indexed in the run
/// ledger like every other stage artifact.
@Suite("Simulation flow stage executor", .timeLimit(.minutes(2)))
struct SimulationFlowStageExecutorTests {

    /// RC low-pass with a DC source: transient starts from the DC
    /// operating point, so V(2) sits at 1V throughout — a deterministic
    /// measurement for the gate.
    private let rcNetlist = """
    * rc lowpass step
    V1 1 0 1
    R1 1 2 1k
    C1 2 0 1n
    .tran 0.1u 5u
    .measure tran vfinal FIND V(2) AT=5u
    .end
    """

    @Test func measurementWithinToleranceGatesPassed() async throws {
        let root = try makeTemporaryRoot("sim-pass")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim",
                intent: "Run simulation",
                stages: [
                    FlowStageDefinition(
                        stageID: "010-sim",
                        displayName: "Simulation",
                        requiredTool: ToolTrustRequirement(
                            kind: .simulation,
                            operationID: "run-simulation",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.spice],
                            requiredOutputFormats: [.csv, .json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.coreSpiceSimulation()]),
            healthResults: [
                "corespice": ToolHealthCheckResult(toolID: "corespice", status: .passed),
            ],
            executors: [
                SimulationFlowStageExecutor(
                    stageID: "010-sim",
                    netlistURL: netlistURL,
                    expectations: [
                        SimulationMeasurementExpectation(name: "vfinal", target: 1.0, tolerance: 0.01),
                    ]
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.first?.gateID == "simulation")
        #expect(stage.gates.first?.status == .passed)
        let artifacts = stage.artifacts
        #expect(artifacts.contains { $0.kind == .waveform && $0.format == .csv })
        #expect(artifacts.contains { $0.kind == .measurement && $0.format == .json })
        #expect(artifacts.contains { $0.kind == .netlist && $0.format == .spice })
        #expect(artifacts.allSatisfy { $0.path.contains(".xcircuite/runs/run-sim/stages/010-sim/raw") })
        #expect(artifacts.allSatisfy { $0.sha256?.isEmpty == false })
    }

    @Test func measurementOutOfToleranceFailsTheGate() async throws {
        let root = try makeTemporaryRoot("sim-fail")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-fail",
                intent: "Run simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(
                    stageID: "010-sim",
                    netlistURL: netlistURL,
                    expectations: [
                        SimulationMeasurementExpectation(name: "vfinal", target: 0.5, tolerance: 0.01),
                    ]
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(stage.gates.first?.status == .failed)
        #expect(stage.diagnostics.contains { $0.code == "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE" })
    }

    @Test func missingMeasurementFailsTheGate() async throws {
        let root = try makeTemporaryRoot("sim-missing")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-missing",
                intent: "Run simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(
                    stageID: "010-sim",
                    netlistURL: netlistURL,
                    expectations: [
                        SimulationMeasurementExpectation(name: "no_such_measure", target: 0, tolerance: 1),
                    ]
                ),
            ]
        )

        #expect(result.stages[0].gates.first?.status == .failed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "SIMULATION_MEASUREMENT_MISSING" })
    }

    @Test func unsupportedAnalysisFailsLoudly() async throws {
        let root = try makeTemporaryRoot("sim-unsupported")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * ac request the stage cannot honor
            V1 1 0 AC 1
            R1 1 2 1k
            C1 2 0 1n
            .ac dec 10 1 1e6
            .end
            """,
            name: "ac.cir",
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-ac",
                intent: "Run simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL),
            ]
        )

        #expect(result.stages[0].gates.first?.status == .failed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "SIMULATION_EXECUTION_ERROR" })
    }

    // MARK: - Helpers

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
