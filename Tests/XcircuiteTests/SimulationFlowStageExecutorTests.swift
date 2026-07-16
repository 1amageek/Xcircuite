import DesignFlowKernel
import Foundation
import Testing
import ToolQualification
import Xcircuite
import DesignFlowKernel

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

        let result = try await makeOrchestrator(root: root).run(
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
            toolRegistry: ToolRegistry(descriptors: [
                SignoffToolDescriptors.coreSpiceSimulation(level: .smokeChecked),
            ]),
            healthResults: [
                "corespice": QualifiedToolFixtures.health(toolID: "corespice", level: .smokeChecked),
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
        #expect(stage.gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        let artifacts = stage.artifacts
        #expect(artifacts.contains { $0.kind == .waveform && $0.format == .csv })
        #expect(artifacts.contains { $0.kind == .measurement && $0.format == .json })
        #expect(artifacts.contains { $0.kind == .netlist && $0.format == .spice })
        let summaryArtifact = try #require(artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "passed")
        #expect(summary.summary.analysis == "tran")
        #expect(summary.summary.waveformVariableCount > 0)
        #expect(summary.waveformVariables.isEmpty == false)
        #expect(summary.summary.expectationCount == 1)
        #expect(summary.summary.failedExpectationCount == 0)
        let envelopeArtifact = try #require(artifacts.first {
            $0.path.hasSuffix("evidence/simulation-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(envelope.artifactID == "simulation-summary")
        #expect(evaluation.status == .accepted)
        #expect(observations.channels.first {
            $0.channelID == "simulation-tool-evidence-count"
        }?.value == .scalar(1))
        #expect(observations.missingChannelIDs.isEmpty)
        #expect(observations.uncalibratedChannelIDs == ["simulation-qualified-calibration"])
        let valueChannel = try #require(observations.channels.first {
            $0.channelID == "simulation-measurement-0-vfinal-value"
        })
        let residualChannel = try #require(observations.channels.first {
            $0.channelID == "simulation-measurement-0-vfinal-residual"
        })
        let withinToleranceChannel = try #require(observations.channels.first {
            $0.channelID == "simulation-measurement-0-vfinal-within-tolerance"
        })
        let waveformVariablesChannel = try #require(observations.channels.first {
            $0.channelID == "simulation-waveform-variable-count"
        })
        #expect(valueChannel.status == .observed)
        #expect(abs((jsonNumber(valueChannel.value) ?? 0) - 1) < 0.000001)
        #expect(valueChannel.unit == "V")
        #expect(residualChannel.status == .observed)
        #expect((jsonNumber(residualChannel.value) ?? 1) < 0.000001)
        #expect(withinToleranceChannel.status == .observed)
        #expect(withinToleranceChannel.value == .boolean(true))
        #expect(waveformVariablesChannel.status == .observed)
        #expect(waveformVariablesChannel.value == .scalar(Double(summary.waveformVariables.count)))
        #expect(evaluation.channelResults.contains {
            $0.channelID == "simulation-measurement-0-vfinal-within-tolerance"
                && $0.status == .accepted
        })
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
        #expect(artifacts.filter { !$0.path.contains("/evidence/") }.allSatisfy {
            $0.path.contains(".xcircuite/runs/run-sim/stages/010-sim/raw")
        })
        #expect(artifacts.allSatisfy { $0.sha256.isEmpty == false })
    }

    @Test func missingAnalysisDirectiveFailsWithoutOperatingPointFallback() async throws {
        let root = try makeTemporaryRoot("sim-missing-analysis")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * missing analysis
            V1 1 0 1
            R1 1 0 1k
            .end
            """,
            name: "missing-analysis.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-missing-analysis",
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
                        SimulationMeasurementExpectation(name: "vfinal", target: 1, tolerance: 0.01),
                    ]
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.status == .failed)
        #expect(stage.diagnostics.contains { $0.code == "SIMULATION_ANALYSIS_MISSING" })
        #expect(!stage.artifacts.contains { $0.kind == .waveform })
    }

    @Test func emptyExpectationsDoNotPassSimulationGateByDefault() async throws {
        let root = try makeTemporaryRoot("sim-empty-expectations")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-empty-expectations",
                intent: "Run simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .incomplete })
        #expect(stage.diagnostics.contains { $0.code == "SIMULATION_EXPECTATIONS_EMPTY" })
        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "incomplete")
        #expect(summary.summary.expectationCount == 0)
    }

    @Test func simulationExecutorRetriesTransientFailureAndPersistsAttempts() async throws {
        let root = try makeTemporaryRoot("sim-retry")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)
        let engineState = FlakySimulationEngineState()

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-retry",
                intent: "Retry transient simulation executor failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "010-sim",
                        displayName: "Simulation",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["SIMULATION_EXECUTION_ERROR"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(
                    stageID: "010-sim",
                    netlistURL: netlistURL,
                    expectations: [
                        SimulationMeasurementExpectation(name: "vfinal", target: 1.0, tolerance: 0.01),
                    ],
                    engine: FlakySimulationEngine(state: engineState)
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(await engineState.executionCount() == 2)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 2)
        #expect(stage.attempts[0].diagnosticCodes.contains("SIMULATION_EXECUTION_ERROR"))
        #expect(stage.attempts[0].retryDecision.reason == .retryableDiagnosticMatched)
        #expect(stage.attempts[1].retryDecision.reason == .stageDidNotFail)
        #expect(stage.artifacts.contains { $0.artifactID == "010-sim-attempts" })

        let attemptsURL = root.appending(path: ".xcircuite/runs/run-sim-retry/stages/010-sim/attempts.json")
        let attempts = try JSONDecoder().decode(
            [FlowStageAttemptRecord].self,
            from: Data(contentsOf: attemptsURL)
        )
        #expect(attempts.map(\.attemptIndex) == [1, 2])
        #expect(attempts[0].retryDecision.matchedDiagnosticCodes == ["SIMULATION_EXECUTION_ERROR"])

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let ledger = try await store.loadRunLedger(runID: "run-sim-retry")
        #expect(ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.stages.first?.attemptCount == 2)
        #expect(summary.stages.first?.retryCount == 1)

        let bundle = try await DefaultFlowRunReviewBundler(
            loader: store,
            persistence: store
        ).makeReviewBundle(
            runID: "run-sim-retry",
            projectRoot: root
        )
        #expect(bundle.artifacts.first(where: { $0.purpose == .stageAttempts }) != nil)
    }

    @Test func waveformArtifactPreservesSemanticNodeAndBranchNames() async throws {
        let root = try makeTemporaryRoot("sim-waveform-names")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * named rc transient
            VDD vdd 0 1.8
            R1 vdd out 1k
            C1 out 0 1n
            .tran 0.1u 1u
            .end
            """,
            name: "named-rc.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-waveform-names",
                intent: "Run named-node simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(stage.status == .succeeded)
        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveformURL = root.appending(path: waveformArtifact.path)
        let waveform = try String(contentsOf: waveformURL, encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        let header = try #require(lines.first)
        let firstDataRow = try #require(lines.dropFirst().first)
        #expect(firstDataRow.split(separator: ",").count == header.split(separator: ",").count)

        #expect(header.contains("V(vdd)"))
        #expect(header.contains("V(out)"))
        #expect(header.contains("I(vdd)"))
    }

    @Test func netlistArtifactDoesNotCollideWithReservedSimulationOutputs() async throws {
        let root = try makeTemporaryRoot("sim-netlist-output-name-collision")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "waveform.csv", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-netlist-output-name-collision",
                intent: "Run simulation with an output-like netlist filename",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        let netlistArtifact = try #require(stage.artifacts.first { $0.kind == .netlist })
        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        #expect(netlistArtifact.path != waveformArtifact.path)
        #expect(netlistArtifact.path.hasSuffix("input-netlist.cir"))
        let retainedNetlist = try String(
            contentsOf: root.appending(path: netlistArtifact.path),
            encoding: .utf8
        )
        let waveform = try String(
            contentsOf: root.appending(path: waveformArtifact.path),
            encoding: .utf8
        )
        #expect(retainedNetlist == rcNetlist)
        #expect(waveform != rcNetlist)
    }

    @Test func stageArtifactInputDigestMismatchReturnsStructuredDiagnostic() async throws {
        let root = try makeTemporaryRoot("sim-stage-artifact-digest")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        let runDirectory = try await prepareTestRun(runID: "run-sim-input-digest", store: workspaceStore)
        let producerRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "005-netlist")
            .appending(path: "raw")
        try FileManager.default.createDirectory(at: producerRawDirectory, withIntermediateDirectories: true)
        let netlistURL = producerRawDirectory.appending(path: "input.cir")
        let netlistData = Data(rcNetlist.utf8)
        try netlistData.write(to: netlistURL, options: [.atomic])
        let netlistPath = ".xcircuite/runs/run-sim-input-digest/stages/005-netlist/raw/input.cir"
        let producerStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "005-netlist")
        try await workspaceStore.writeJSON(
            FlowStageResult(
                stageID: "005-netlist",
                status: .succeeded,
                artifacts: [
                    try artifactReference(try fixtureArtifactReference(
                        artifactID: "source-netlist",
                        path: netlistPath,
                        kind: .netlist,
                        format: .spice,
                        sha256: String(repeating: "0", count: 64),
                        byteCount: Int64(netlistData.count),
                    )),
                ]
            ),
            to: ".xcircuite/runs/run-sim-input-digest/stages/005-netlist/result.json"
        )

        let result = try await SimulationFlowStageExecutor(
            stageID: "010-sim",
            netlistInput: .stageArtifact(
                XcircuiteFlowInputReference.StageArtifact(
                    stageID: "005-netlist",
                    artifactID: "source-netlist",
                    kind: .netlist,
                    format: .spice
                )
            )
        ).execute(
            stage: FlowStageDefinition(stageID: "010-sim", displayName: "Simulation"),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: "run-sim-input-digest",
                runDirectory: runDirectory,
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "SIMULATION_INPUT_ARTIFACT_DIGEST_MISMATCH"
                && $0.message.contains("digest mismatch")
        })
        #expect(result.gates.contains { gate in
            gate.gateID == "simulation"
                && gate.diagnostics.contains { $0.code == "SIMULATION_INPUT_ARTIFACT_DIGEST_MISMATCH" }
        })
    }

    @Test func measurementOutOfToleranceFailsTheGate() async throws {
        let root = try makeTemporaryRoot("sim-fail")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
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
        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "failed")
        #expect(summary.summary.failedExpectationCount == 1)
        #expect(summary.expectations.first?.status == "failed")
        let envelopeArtifact = try #require(stage.artifacts.first {
            $0.path.hasSuffix("evidence/simulation-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        let withinToleranceChannel = try #require(observations.channels.first {
            $0.channelID == "simulation-measurement-0-vfinal-within-tolerance"
        })
        let channelResult = try #require(evaluation.channelResults.first {
            $0.channelID == "simulation-measurement-0-vfinal-within-tolerance"
        })
        #expect(withinToleranceChannel.value == .boolean(false))
        #expect(evaluation.status == .rejected)
        #expect(channelResult.status == .rejected)
        #expect((channelResult.residual ?? 0) > 1)
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
    }

    @Test func missingMeasurementFailsTheGate() async throws {
        let root = try makeTemporaryRoot("sim-missing")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
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
        let summaryArtifact = try #require(result.stages[0].artifacts.first {
            $0.artifactID == "simulation-summary"
        })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "failed")
        #expect(summary.expectations.first?.status == "missing")
        let envelopeArtifact = try #require(result.stages[0].artifacts.first {
            $0.path.hasSuffix("evidence/simulation-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(observations.missingChannelIDs.contains("simulation-measurement-0-no-such-measure-value"))
        #expect(observations.missingChannelIDs.contains("simulation-measurement-0-no-such-measure-residual"))
        #expect(observations.missingChannelIDs.contains("simulation-measurement-0-no-such-measure-within-tolerance"))
        #expect(evaluation.feedbackSignals.first?.routingLevel == .structureMapping)
    }

    @Test func simulationExecutorCooperativelyCancelsAfterEngineCheckpoint() async throws {
        let root = try makeTemporaryRoot("sim-cooperative-cancel")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(rcNetlist, name: "rc.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-cancel",
                intent: "Run cancellable simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(
                    stageID: "010-sim",
                    netlistURL: netlistURL,
                    engine: CancellingSimulationEngine(projectRoot: root, runID: "run-sim-cancel")
                ),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .cancelled)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root).loadRunLedger(runID: "run-sim-cancel")
        #expect(ledger.cancellationRequest?.requestedBy == "corespice")
        #expect(ledger.progressEvents.contains { $0.kind == .cancellationObserved })
    }

    @Test func acAnalysisRunsFromFlowStageAndPersistsComplexWaveform() async throws {
        let root = try makeTemporaryRoot("sim-ac")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * ac request
            V1 1 0 AC 1
            R1 1 2 1k
            C1 2 0 1n
            .ac lin 3 1k 3k
            .end
            """,
            name: "ac.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-ac",
                intent: "Run simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "ac")
        #expect(summary.summary.waveformVariableCount > 0)
        #expect(summary.waveformVariables.contains { $0.hasSuffix("_real") })
        #expect(summary.waveformVariables.contains { $0.hasSuffix("_imag") })

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count == 4)
        let header = try #require(lines.first)
        let firstDataRow = try #require(lines.dropFirst().first)
        #expect(header.contains("_real"))
        #expect(header.contains("_imag"))
        #expect(firstDataRow.split(separator: ",").count == header.split(separator: ",").count)
    }

    @Test func dcSweepRunsFromFlowStageAndPersistsSweepWaveform() async throws {
        let root = try makeTemporaryRoot("sim-dc")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * dc sweep request
            V1 in 0 0
            R1 in 0 1k
            .dc V1 0 1 0.5
            .end
            """,
            name: "dc.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-dc",
                intent: "Run DC sweep simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "dc")
        #expect(summary.waveformVariables.contains("V(in)"))

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count == 4)
        let header = try #require(lines.first)
        let sweepValues = lines.dropFirst().compactMap { line -> Double? in
            Double(line.split(separator: ",")[0])
        }
        #expect(header.starts(with: "v1,"))
        #expect(sweepValues == [0.0, 0.5, 1.0])
    }

    @Test func dcSweepRejectsUnknownSourceName() async throws {
        await #expect(throws: CoreSpiceSimulationEngine.EngineError.unsupportedAnalysis(
            ".dc source vin did not match any independent source; available sources: v1"
        )) {
            _ = try await CoreSpiceSimulationEngine().run(
                netlistSource: """
                * dc sweep request
                V1 in 0 0
                R1 in 0 1k
                .dc VIN 0 1 0.5
                .end
                """,
                fileName: "unknown-dc-source.cir"
            )
        }
    }

    @Test func dcSweepRejectsNonSourceDeviceName() async throws {
        await #expect(throws: CoreSpiceSimulationEngine.EngineError.unsupportedAnalysis(
            ".dc source r1 resolved to unsupported device type resistor; sweep source must be an independent voltage or current source"
        )) {
            _ = try await CoreSpiceSimulationEngine().run(
                netlistSource: """
                * dc sweep request
                V1 in 0 0
                R1 in 0 1k
                .dc R1 0 1 0.5
                .end
                """,
                fileName: "non-source-dc-source.cir"
            )
        }
    }

    @Test func monteCarloDCSweepRejectsUnknownSourceName() async throws {
        await #expect(throws: CoreSpiceSimulationEngine.EngineError.unsupportedAnalysis(
            ".mc .dc source vin did not match any independent source; available sources: v1"
        )) {
            _ = try await CoreSpiceSimulationEngine().run(
                netlistSource: """
                * monte carlo dc sweep request
                V1 in 0 0
                R1 in 0 1k
                .mc 2 dc VIN 0 1 0.5 seed=7
                .end
                """,
                fileName: "unknown-mc-dc-source.cir"
            )
        }
    }

    @Test func monteCarloDCSweepRejectsNonSourceDeviceName() async throws {
        await #expect(throws: CoreSpiceSimulationEngine.EngineError.unsupportedAnalysis(
            ".mc .dc source r1 resolved to unsupported device type resistor; sweep source must be an independent voltage or current source"
        )) {
            _ = try await CoreSpiceSimulationEngine().run(
                netlistSource: """
                * monte carlo dc sweep request
                V1 in 0 0
                R1 in 0 1k
                .mc 2 dc R1 0 1 0.5 seed=7
                .end
                """,
                fileName: "non-source-mc-dc-source.cir"
            )
        }
    }

    @Test func transferFunctionRunsFromFlowStageAndPersistsScalarWaveform() async throws {
        let root = try makeTemporaryRoot("sim-tf")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * transfer function request
            V1 in 0 5
            R1 in out 1k
            R2 out 0 1k
            .tf V(out) V1
            .end
            """,
            name: "tf.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-tf",
                intent: "Run transfer function simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "tf")
        #expect(summary.waveformVariables == ["gain", "Zin", "Zout"])

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first == "point,gain,Zin,Zout")
        let values = try #require(lines.dropFirst().first).split(separator: ",").compactMap { Double($0) }
        #expect(values.count == 4)
        #expect(abs(values[1] - 0.5) < 0.000001)
    }

    @Test func sensitivityRunsFromFlowStageAndPersistsParameterWaveform() async throws {
        let root = try makeTemporaryRoot("sim-sens")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * sensitivity request
            V1 in 0 5
            R1 in out 1k
            R2 out 0 1k
            .sens V(out)
            .end
            """,
            name: "sens.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-sens",
                intent: "Run sensitivity simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "sens")
        #expect(summary.waveformVariables == ["sensitivity", "normalized_sensitivity"])

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count >= 3)
        #expect(lines.first == "parameter,sensitivity,normalized_sensitivity")
    }

    @Test func noiseAnalysisRunsFromFlowStageAndPersistsNoiseWaveform() async throws {
        let root = try makeTemporaryRoot("sim-noise")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * noise request
            V1 in 0 1
            R1 in out 1k
            R2 out 0 1k
            .noise V(out) V1 lin 3 1k 3k
            .end
            """,
            name: "noise.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-noise",
                intent: "Run noise simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "noise")
        #expect(summary.waveformVariables.contains("output_noise_density"))
        #expect(summary.waveformVariables.contains("input_referred_noise_density"))

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines.first == "frequency,output_noise_density,input_referred_noise_density,integrated_output_noise")
    }

    @Test func poleZeroRunsFromFlowStageAndPersistsComplexWaveform() async throws {
        let root = try makeTemporaryRoot("sim-pz")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * pole-zero request
            V1 in 0 1
            R1 in out 1k
            C1 out 0 1n
            .pz in 0 out 0 vol pz
            .end
            """,
            name: "pz.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-pz",
                intent: "Run pole-zero simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "pz")
        #expect(summary.waveformVariables.contains { $0.hasPrefix("pole_real") })
        #expect(summary.waveformVariables.contains { $0.hasPrefix("zero_real") })
        #expect(summary.waveformVariables.contains { $0.hasPrefix("dc_gain_real") })

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count >= 2)
        let header = try #require(lines.first)
        #expect(header.contains("pole_real"))
        #expect(header.contains("zero_real"))
        #expect(header.contains("dc_gain_real"))
    }

    @Test func fourierRunsFromFlowStageAndPersistsHarmonicWaveform() async throws {
        let root = try makeTemporaryRoot("sim-four")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * fourier request
            V1 in 0 PULSE(0 1 0 0.05u 0.05u 0.45u 1u)
            R1 in out 1k
            C1 out 0 1p
            .tran 0.05u 3u
            .four 1meg V(out)
            .end
            """,
            name: "four.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-four",
                intent: "Run Fourier simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "four")
        #expect(summary.waveformVariables.contains { $0.hasSuffix("_mag") })
        #expect(summary.waveformVariables.contains { $0.hasSuffix("_phase") })

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count >= 3)
        let header = try #require(lines.first)
        #expect(header.starts(with: "harmonic,"))
        #expect(header.contains("_mag"))
        #expect(header.contains("_phase"))
    }

    @Test func monteCarloRunsFromFlowStageAndPersistsStatisticsWaveform() async throws {
        let root = try makeTemporaryRoot("sim-mc")
        defer { removeTemporaryRoot(root) }
        let netlistURL = try writeText(
            """
            * monte carlo request
            V1 in 0 0
            R1 in 0 {gauss(1000, 100)}
            .mc 5 dc V1 0 1 0.5 seed=17
            .end
            """,
            name: "mc.cir",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-sim-mc",
                intent: "Run Monte Carlo simulation",
                stages: [FlowStageDefinition(stageID: "010-sim", displayName: "Simulation")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
            healthResults: [:],
            executors: [
                SimulationFlowStageExecutor(stageID: "010-sim", netlistURL: netlistURL, allowObservationOnly: true),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed })

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "simulation-summary" })
        let summary = try decodeSimulationSummary(summaryArtifact, root: root)
        #expect(summary.summary.analysis == "mc")
        #expect(summary.waveformVariables == ["point", "mean", "stdev", "min", "max", "p5", "p95"])

        let waveformArtifact = try #require(stage.artifacts.first { $0.kind == .waveform })
        let waveform = try String(contentsOf: root.appending(path: waveformArtifact.path), encoding: .utf8)
        let lines = waveform.split(separator: "\n")
        #expect(lines.count > 1)
        #expect(lines.first == "variable,point,mean,stdev,min,max,p5,p95")
        let currentRows = lines.dropFirst().filter { $0.lowercased().hasPrefix("i(v1),") }
        #expect(currentRows.isEmpty == false)
        let stdevs = currentRows.compactMap { row -> Double? in
            let columns = row.split(separator: ",")
            guard columns.count > 3 else { return nil }
            return Double(columns[3])
        }
        #expect(stdevs.contains { $0 > 0 })
    }

    // MARK: - Helpers

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func decodeSimulationSummary(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> SimulationRunSummaryReport {
        try JSONDecoder().decode(
            SimulationRunSummaryReport.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func decodeArtifactEnvelope(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> FlowArtifactEnvelope {
        try JSONDecoder().decode(
            FlowArtifactEnvelope.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func jsonNumber(_ value: FlowMetricValue?) -> Double? {
        guard let value else {
            return nil
        }
        if case .scalar(let number) = value {
            return number
        }
        return nil
    }

    private func makeOrchestrator(root: URL) throws -> DefaultFlowOrchestrator {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        return DefaultFlowOrchestrator(
            infrastructure: store,
            ledgerPersistence: store,
            progressStore: FlowRunProgressStore(persistence: store)
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private struct CancellingSimulationEngine: SimulationExecuting {
        let projectRoot: URL
        let runID: String

        func run(netlistSource: String, fileName: String?) async throws -> SimulationStageOutcome {
            let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
            _ = try await DefaultFlowRunCancellationRecorder(
                progressStore: FlowRunProgressStore(persistence: store)
            ).requestCancellation(
                projectRoot: projectRoot,
                runID: runID,
                requestedBy: "corespice",
                reason: "cooperative simulation cancellation checkpoint"
            )
            return SimulationStageOutcome(
                analysisLabel: "tran",
                measurements: [
                    SimulationMeasurementValue(name: "vfinal", value: 1.0, unit: "V"),
                ],
                waveformCSV: "time,V(out)\n0,1\n"
            )
        }
    }

    private struct FlakySimulationEngine: SimulationExecuting {
        let state: FlakySimulationEngineState

        func run(netlistSource: String, fileName: String?) async throws -> SimulationStageOutcome {
            try await state.run(netlistSource: netlistSource, fileName: fileName)
        }
    }

    private actor FlakySimulationEngineState {
        private var runCount = 0

        func run(netlistSource: String, fileName: String?) async throws -> SimulationStageOutcome {
            runCount += 1
            if runCount == 1 {
                throw TransientSimulationError()
            }
            return try await CoreSpiceSimulationEngine().run(netlistSource: netlistSource, fileName: fileName)
        }

        func executionCount() -> Int {
            runCount
        }
    }

    private struct TransientSimulationError: Error {}
}
