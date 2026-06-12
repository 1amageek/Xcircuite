import DesignFlowKernel
import Foundation
import XcircuitePackage

/// Simulation as a first-class flow stage, at the same maturity as
/// DRC/LVS/PEX: the netlist's own analysis runs in-process (CoreSpice),
/// the gate judges convergence plus every declared measurement
/// expectation, and the waveform + measurements land in the run ledger
/// as indexed artifacts.
public struct SimulationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let netlistURL: URL
    private let expectations: [SimulationMeasurementExpectation]
    private let engine: any SimulationExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String = "corespice",
        netlistURL: URL,
        expectations: [SimulationMeasurementExpectation] = [],
        engine: any SimulationExecuting = CoreSpiceSimulationEngine()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.netlistURL = netlistURL
        self.expectations = expectations
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try validate(stage: stage)
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try context.packageStore.ensureDirectory(at: rawDirectory)

            // The run captures its own input: the netlist is copied in
            // so the stage stays reviewable after the source moves.
            let source = try String(contentsOf: netlistURL, encoding: .utf8)
            let netlistCopy = rawDirectory.appending(path: netlistURL.lastPathComponent)
            try context.packageStore.writeText(source, to: netlistCopy)

            let outcome = try await engine.run(
                netlistSource: source,
                fileName: netlistURL.lastPathComponent
            )

            let waveformURL = rawDirectory.appending(path: "waveform.csv")
            try context.packageStore.writeText(outcome.waveformCSV, to: waveformURL)
            let measurementsURL = rawDirectory.appending(path: "measurements.json")
            try context.packageStore.writeJSON(
                outcome.measurements,
                to: measurementsURL,
                forProjectAt: context.projectRoot
            )

            let verdicts = expectationVerdicts(outcome: outcome)
            let diagnostics = verdicts.diagnostics
            let gateStatus: FlowGateStatus = verdicts.failures == 0 ? .passed : .failed

            return FlowStageResult(
                stageID: stage.stageID,
                status: gateStatus == .passed ? .succeeded : .failed,
                diagnostics: diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "simulation",
                        status: gateStatus,
                        diagnostics: diagnostics
                    ),
                ],
                artifacts: [
                    try artifactBuilder.reference(
                        for: netlistCopy,
                        projectRoot: context.projectRoot,
                        kind: .netlist,
                        format: .spice,
                        producedByRunID: context.runID
                    ),
                    try artifactBuilder.reference(
                        for: waveformURL,
                        projectRoot: context.projectRoot,
                        kind: .waveform,
                        format: .csv,
                        producedByRunID: context.runID
                    ),
                    try artifactBuilder.reference(
                        for: measurementsURL,
                        projectRoot: context.projectRoot,
                        kind: .measurement,
                        format: .json,
                        producedByRunID: context.runID
                    ),
                ]
            )
        } catch {
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "SIMULATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "simulation",
                        status: .failed,
                        diagnostics: [diagnostic]
                    ),
                ]
            )
        }
    }

    // MARK: - Gate

    private func expectationVerdicts(
        outcome: SimulationStageOutcome
    ) -> (diagnostics: [FlowDiagnostic], failures: Int) {
        var diagnostics: [FlowDiagnostic] = [
            FlowDiagnostic(
                severity: .info,
                code: "SIMULATION_ANALYSIS",
                message: "ran \(outcome.analysisLabel) with \(outcome.measurements.count) measurement(s)"
            ),
        ]
        var failures = 0
        let measured = Dictionary(
            outcome.measurements.map { ($0.name.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        for expectation in expectations {
            guard let value = measured[expectation.name.lowercased()] else {
                failures += 1
                diagnostics.append(FlowDiagnostic(
                    severity: .error,
                    code: "SIMULATION_MEASUREMENT_MISSING",
                    message: "expected measurement '\(expectation.name)' was not produced"
                ))
                continue
            }
            if abs(value - expectation.target) > expectation.tolerance {
                failures += 1
                diagnostics.append(FlowDiagnostic(
                    severity: .error,
                    code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                    message: "'\(expectation.name)' = \(value), expected \(expectation.target) ± \(expectation.tolerance)"
                ))
            } else {
                diagnostics.append(FlowDiagnostic(
                    severity: .info,
                    code: "SIMULATION_MEASUREMENT_OK",
                    message: "'\(expectation.name)' = \(value) within \(expectation.target) ± \(expectation.tolerance)"
                ))
            }
        }
        return (diagnostics, failures)
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }
}
