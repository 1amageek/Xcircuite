import CircuiteFoundation
import CoreSpice
import DesignFlowKernel
import Foundation

/// Simulation as a first-class flow stage, at the same maturity as
/// DRC/LVS/PEX: the netlist's own analysis runs in-process (CoreSpice),
/// the gate judges convergence plus every declared measurement
/// expectation, and the waveform + measurements land in the run ledger
/// as indexed artifacts.
public struct SimulationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let netlistInput: XcircuiteFlowInputReference
    private let expectations: [SimulationMeasurementExpectation]
    private let allowObservationOnly: Bool
    private let engine: any SimulationExecuting

    public init(
        stageID: String,
        toolID: String = "corespice",
        netlistURL: URL,
        expectations: [SimulationMeasurementExpectation] = [],
        allowObservationOnly: Bool = false,
        engine: any SimulationExecuting = CoreSpiceSimulationEngine()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.netlistInput = .path(netlistURL.path(percentEncoded: false))
        self.expectations = expectations
        self.allowObservationOnly = allowObservationOnly
        self.engine = engine
    }

    public init(
        stageID: String,
        toolID: String = "corespice",
        netlistInput: XcircuiteFlowInputReference,
        expectations: [SimulationMeasurementExpectation] = [],
        allowObservationOnly: Bool = false,
        engine: any SimulationExecuting = CoreSpiceSimulationEngine()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.netlistInput = netlistInput
        self.expectations = expectations
        self.allowObservationOnly = allowObservationOnly
        self.engine = engine
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            try await context.checkCancellation()

            // The run captures its own input: the netlist is copied in
            // so the stage stays reviewable after the source moves.
            let resolvedNetlistURL = try await netlistInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let source = try String(contentsOf: resolvedNetlistURL, encoding: .utf8)
            let netlistReference = try await context.persistArtifact(
                Data(source.utf8),
                artifactID: "simulation-input-netlist",
                stageID: stageID,
                fileName: "input-netlist.cir",
                role: .input,
                kind: .netlist,
                format: .spice,
                mode: .immutable
            )
            try await context.checkCancellation()

            let outcome = try await engine.execute(SimulationExecutionRequest(
                netlistSource: source,
                fileName: resolvedNetlistURL.lastPathComponent,
                inputs: [netlistReference]
            ))
            try await context.checkCancellation()
            try validateLineage(outcome: outcome, input: netlistReference)
            let producer = outcome.coreSpiceResult.provenance.producer

            let waveformReference = try await context.persistArtifact(
                Data(outcome.waveformCSV.utf8),
                artifactID: "simulation-waveform",
                stageID: stageID,
                fileName: "waveform.csv",
                kind: .waveform,
                format: .csv,
                producer: producer,
                mode: .replaceable
            )
            let measurementsReference = try await context.persistJSONArtifact(
                outcome.measurements,
                artifactID: "simulation-measurements",
                stageID: stageID,
                fileName: "measurements.json",
                kind: .measurement,
                producer: producer,
                mode: .replaceable
            )
            let canonicalResult = CoreSpiceSimulationResult(
                artifacts: outcome.coreSpiceResult.artifacts + [
                    waveformReference,
                    measurementsReference,
                ],
                diagnostics: outcome.coreSpiceResult.diagnostics,
                provenance: outcome.coreSpiceResult.provenance
            )
            let canonicalResultReference = try await context.persistJSONArtifact(
                canonicalResult,
                artifactID: "corespice-simulation-result",
                stageID: stageID,
                fileName: "corespice-result.json",
                kind: .report,
                producer: producer,
                mode: .replaceable
            )

            let verdicts = expectationVerdicts(outcome: outcome)
            let diagnostics = verdicts.diagnostics
            let gateStatus = verdicts.gateStatus
            let summary = SimulationRunSummaryReport.make(
                stageID: stage.stageID,
                toolID: toolID,
                outcome: outcome,
                expectationResults: verdicts.expectationResults,
                gateStatus: gateStatus,
                diagnostics: diagnostics
            )
            let summaryReference = try await context.persistJSONArtifact(
                summary,
                artifactID: "simulation-summary",
                stageID: stageID,
                fileName: "simulation-summary.json",
                kind: .report,
                producer: producer,
                mode: .replaceable
            )

            var artifacts = outcome.coreSpiceResult.artifacts + [
                netlistReference,
                waveformReference,
                measurementsReference,
                canonicalResultReference,
                summaryReference,
            ]
            let preEnvelopeArtifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            if preEnvelopeArtifactIntegrityGate.status != .passed {
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .failed,
                    diagnostics: diagnostics + preEnvelopeArtifactIntegrityGate.diagnostics,
                    gates: [
                        FlowGateResult(
                            gateID: "simulation",
                            status: gateStatus,
                            diagnostics: diagnostics
                        ),
                        preEnvelopeArtifactIntegrityGate,
                    ],
                    artifacts: artifacts
                )
            }
            let envelopeArtifact = try await SimulationSummaryEnvelopeBuilder().envelopeReference(
                summary: summary,
                summaryArtifactID: "simulation-summary",
                stageArtifacts: artifacts,
                gateStatus: gateStatus,
                diagnostics: diagnostics,
                stageID: stage.stageID,
                toolID: toolID,
                context: context
            )
            artifacts.append(envelopeArtifact)
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let stageStatus: FlowStageStatus = gateStatus == .passed
                && artifactIntegrityGate.status == .passed
                ? .succeeded
                : .failed

            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics + artifactIntegrityGate.diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "simulation",
                        status: gateStatus,
                        diagnostics: diagnostics
                    ),
                    artifactIntegrityGate,
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = diagnostic(for: error)
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

    private func validateLineage(
        outcome: SimulationStageOutcome,
        input: ArtifactReference
    ) throws {
        let provenance = outcome.coreSpiceResult.provenance
        guard provenance.inputs == [input] else {
            throw SimulationArtifactLineageError.inputMismatch
        }
        guard provenance.producer.identifier == toolID else {
            throw SimulationArtifactLineageError.producerMismatch(
                expected: toolID,
                actual: provenance.producer.identifier
            )
        }
        for artifact in outcome.coreSpiceResult.artifacts
        where artifact.producer != provenance.producer {
            throw SimulationArtifactLineageError.outputProducerMismatch(path: artifact.path)
        }
    }

    private func expectationVerdicts(
        outcome: SimulationStageOutcome
    ) -> (
        diagnostics: [FlowDiagnostic],
        failures: Int,
        gateStatus: FlowGateStatus,
        expectationResults: [SimulationRunSummaryReport.ExpectationResult]
    ) {
        var diagnostics: [FlowDiagnostic] = [
            FlowDiagnostic(
                severity: .info,
                code: "SIMULATION_ANALYSIS",
                message: "ran \(outcome.analysisLabel) with \(outcome.measurements.count) measurement(s)"
            ),
        ]
        var failures = 0
        var expectationResults: [SimulationRunSummaryReport.ExpectationResult] = []
        guard !expectations.isEmpty else {
            if allowObservationOnly {
                diagnostics.append(FlowDiagnostic(
                    severity: .info,
                    code: "SIMULATION_OBSERVATION_ONLY",
                    message: "simulation ran without measurement expectations by explicit observation-only policy"
                ))
                return (diagnostics, failures, .passed, expectationResults)
            }
            diagnostics.append(FlowDiagnostic(
                severity: .error,
                code: "SIMULATION_EXPECTATIONS_EMPTY",
                message: "simulation gate requires at least one measurement expectation"
            ))
            return (diagnostics, 1, .incomplete, expectationResults)
        }
        let measured = Dictionary(
            outcome.measurements.map { ($0.name.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        for expectation in expectations {
            guard let value = measured[expectation.name.lowercased()] else {
                failures += 1
                expectationResults.append(SimulationRunSummaryReport.ExpectationResult(
                    name: expectation.name,
                    target: expectation.target,
                    tolerance: expectation.tolerance,
                    measuredValue: nil,
                    status: "missing",
                    residual: nil
                ))
                diagnostics.append(FlowDiagnostic(
                    severity: .error,
                    code: "SIMULATION_MEASUREMENT_MISSING",
                    message: "expected measurement '\(expectation.name)' was not produced"
                ))
                continue
            }
            if abs(value - expectation.target) > expectation.tolerance {
                failures += 1
                expectationResults.append(SimulationRunSummaryReport.ExpectationResult(
                    name: expectation.name,
                    target: expectation.target,
                    tolerance: expectation.tolerance,
                    measuredValue: value,
                    status: "failed",
                    residual: abs(value - expectation.target)
                ))
                diagnostics.append(FlowDiagnostic(
                    severity: .error,
                    code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                    message: "'\(expectation.name)' = \(value), expected \(expectation.target) ± \(expectation.tolerance)"
                ))
            } else {
                expectationResults.append(SimulationRunSummaryReport.ExpectationResult(
                    name: expectation.name,
                    target: expectation.target,
                    tolerance: expectation.tolerance,
                    measuredValue: value,
                    status: "passed",
                    residual: abs(value - expectation.target)
                ))
                diagnostics.append(FlowDiagnostic(
                    severity: .info,
                    code: "SIMULATION_MEASUREMENT_OK",
                    message: "'\(expectation.name)' = \(value) within \(expectation.target) ± \(expectation.tolerance)"
                ))
            }
        }
        return (diagnostics, failures, failures == 0 ? .passed : .failed, expectationResults)
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = FlowIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func diagnostic(for error: any Error) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: diagnosticCode(for: error),
            message: diagnosticMessage(for: error)
        )
    }

    private func diagnosticCode(for error: any Error) -> String {
        if let runtimeError = error as? XcircuiteRuntimeError {
            switch runtimeError {
            case .artifactReferenceAmbiguous:
                return "SIMULATION_INPUT_ARTIFACT_AMBIGUOUS"
            case .artifactReferenceByteCountMismatch:
                return "SIMULATION_INPUT_ARTIFACT_BYTE_COUNT_MISMATCH"
            case .artifactReferenceDigestMismatch:
                return "SIMULATION_INPUT_ARTIFACT_DIGEST_MISMATCH"
            case .artifactReferenceMissingByteCount:
                return "SIMULATION_INPUT_ARTIFACT_MISSING_BYTE_COUNT"
            case .artifactReferenceMissingDigest:
                return "SIMULATION_INPUT_ARTIFACT_MISSING_DIGEST"
            case .artifactReferenceNotFound:
                return "SIMULATION_INPUT_ARTIFACT_NOT_FOUND"
            case .artifactOutsideProject:
                return "SIMULATION_ARTIFACT_OUTSIDE_PROJECT"
            case .inputReferenceMissing:
                return "SIMULATION_INPUT_REFERENCE_MISSING"
            case .invalidInputReference:
                return "SIMULATION_INPUT_REFERENCE_INVALID"
            case .invalidConfiguration:
                return "SIMULATION_RUNTIME_CONFIGURATION_INVALID"
            case .invalidFlowInfrastructure:
                return "SIMULATION_FLOW_INFRASTRUCTURE_INVALID"
            case .stageMismatch:
                return "SIMULATION_STAGE_MISMATCH"
            }
        }
        if let specError = error as? XcircuiteFlowRuntimeSpecError {
            switch specError {
            case .invalidPath:
                return "SIMULATION_INPUT_REFERENCE_INVALID"
            default:
                break
            }
        }
        if let engineError = error as? CoreSpiceSimulationEngine.EngineError {
            switch engineError {
            case .missingAnalysisDirective:
                return "SIMULATION_ANALYSIS_MISSING"
            case .unsupportedAnalysis:
                return "SIMULATION_ANALYSIS_UNSUPPORTED"
            case .missingDeviceDescriptor:
                return "SIMULATION_DEVICE_DESCRIPTOR_MISSING"
            }
        }
        if error is SimulationArtifactLineageError {
            return "SIMULATION_ARTIFACT_LINEAGE_INVALID"
        }
        return "SIMULATION_EXECUTION_ERROR"
    }

    private func diagnosticMessage(for error: any Error) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
