import Foundation
import CircuiteFoundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite numeric repair loop runner")
struct XcircuiteNumericRepairLoopRunnerTests {
    @Test func numericRepairLoopCLIExecutesRejectedFeedbackLoopUntilSimulationMetricPasses() async throws {
        let root = try makeTemporaryRoot("simulation-metric-loop")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-1", store: store)
        try await writeText(
            """
            * resistor divider repair
            V1 1 0 dc 2
            R1 1 2 1000
            R2 2 0 1000
            .op
            .meas op vfinal find V(2) at=0
            .end
            """,
            path: "circuits/rc.cir",
            root: root
        )
        _ = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            makeNumericRepairProblem(runID: "run-1"),
            runID: "run-1",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "run-numeric-repair-loop",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--max-candidates",
            "5",
            "--max-iterations",
            "3",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteNumericRepairLoopResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "accepted")
        #expect(result.accepted)
        #expect(result.iterationCount == 2)
        #expect(result.acceptedIterationIndex == 2)
        #expect(result.iterations.map(\.status) == ["rejected", "accepted"])
        #expect(result.iterations[1].skippedRejectedCandidateIDs.contains(result.iterations[0].selectedCandidateID ?? ""))

        let loopArtifact = try await store.readJSON(
            XcircuiteNumericRepairLoopResult.self,
            from: result.loopArtifactPath
        )
        #expect(loopArtifact.status == "accepted")
        #expect(loopArtifact.iterations[1].accepted)
        #expect(loopArtifact.iterations.allSatisfy { !$0.archivedArtifactRefs.isEmpty })

        let finalReportRef = try #require(result.iterations[1].producedArtifacts.first {
            $0.artifactID == "candidate-step-1-netlist-parameter-edit-report"
        })
        let finalReport = try await store.readJSON(
            XcircuiteNetlistParameterEditReport.self,
            from: finalReportRef.path
        )
        let finalEdit = try #require(finalReport.edits.first { $0.assignmentName == "R1" })
        #expect(finalEdit.value == 1250)

        let rejectedPlansRef = try #require(result.iterations[0].rejectedPlansArtifact)
        let rejectedRecords = try await readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: rejectedPlansRef.path,
            store: store
        )
        #expect(rejectedRecords.count == 1)
        #expect(rejectedRecords.map(\.sourceParameterCandidateIDs).contains([
            try #require(result.iterations[0].selectedCandidateID),
        ]))

        let manifest = try await store.loadRunLedger(runID: "run-1").runManifest
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
                && $0.path == result.loopArtifactPath
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == "planning-numeric-repair-loop-iteration-1-candidate-plan"
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == "planning-numeric-repair-loop-iteration-2-plan-verification"
        })
    }

    @Test func cp7FeedbackPolicyGeneratesCalibrationArtifactsBeforeRetry() async throws {
        let root = try makeTemporaryRoot("cp7-feedback-policy")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-cp7", store: store)
        try await writeText(
            """
            * resistor divider repair
            V1 1 0 dc 2
            R1 1 2 1000
            R2 2 0 1000
            .op
            .meas op vfinal find V(2) at=0
            .end
            """,
            path: "circuits/rc.cir",
            root: root
        )
        _ = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            makeNumericRepairProblem(runID: "run-cp7"),
            runID: "run-cp7",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "run-numeric-repair-loop",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-cp7",
            "--max-candidates",
            "5",
            "--max-iterations",
            "3",
            "--calibration-policy",
            "cp7-feedback",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteNumericRepairLoopResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "accepted")
        #expect(result.calibrationPolicy == "cp7-feedback")
        #expect(result.iterations.map(\.candidateGenerationStrategy) == [
            "adaptive-bounded-refinement",
            "calibrated-feedback-aware-bounded-refinement",
        ])
        let traces = try #require(result.policyTraces)
        #expect(traces.count == 2)
        #expect(traces[0].usesCalibrationArtifacts == false)
        #expect(traces[0].reasonCodes.contains("initial-iteration"))
        #expect(traces[1].usesCalibrationArtifacts)
        #expect(traces[1].sourceIterationIndexes == [1])
        #expect(traces[1].reasonCodes.contains("cp7-artifacts-generated"))
        #expect(traces[1].metricThresholdProfileArtifact?.artifactID == XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID)
        #expect(traces[1].costCalibrationArtifact?.artifactID == XcircuitePlanningArtifactStore.costCalibrationArtifactID)
        #expect(traces[1].paretoCandidatesArtifact?.artifactID == XcircuitePlanningArtifactStore.paretoCandidatesArtifactID)
        #expect(traces[1].improvementLoopArtifact?.artifactID == XcircuitePlanningArtifactStore.improvementLoopArtifactID)

        let retryTrace = try #require(result.iterations[1].policyTrace)
        #expect(retryTrace.selectedCandidateStrategy == "calibrated-feedback-aware-bounded-refinement")
        #expect(retryTrace.paretoCandidatesArtifact?.path == traces[1].paretoCandidatesArtifact?.path)

        let searchTraceRef = try #require(result.iterations[1].searchTraceArtifact)
        let searchTrace = try await store.readJSON(
            XcircuiteParameterCandidateSearchTrace.self,
            from: searchTraceRef.path
        )
        #expect(searchTrace.strategy == "calibrated-feedback-aware-bounded-refinement")
        let calibrationTrace = try #require(searchTrace.calibrationTrace)
        #expect(calibrationTrace.costCalibrationPath != nil)
        #expect(calibrationTrace.paretoCandidatesPath != nil)
        #expect(calibrationTrace.paretoCandidateCount >= 1)

        let manifest = try await store.loadRunLedger(runID: "run-cp7").runManifest
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.costCalibrationArtifactID
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.paretoCandidatesArtifactID
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.improvementLoopArtifactID
        })
    }

    @Test func numericRepairLoopDoesNotOverwriteExistingIterationArchives() async throws {
        let root = try makeTemporaryRoot("archive-overwrite-guard")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-archive-guard"
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        try await writeText(
            """
            * resistor divider repair
            V1 1 0 dc 2
            R1 1 2 1000
            R2 2 0 1000
            .op
            .meas op vfinal find V(2) at=0
            .end
            """,
            path: "circuits/rc.cir",
            root: root
        )
        _ = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            makeNumericRepairProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )

        let firstJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "run-numeric-repair-loop",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--max-candidates",
            "5",
            "--max-iterations",
            "3",
            "--pretty",
        ])
        let firstResult = try JSONDecoder().decode(
            XcircuiteNumericRepairLoopResult.self,
            from: try #require(firstJSON.data(using: .utf8))
        )
        let archivedCandidates = try #require(firstResult.iterations[0].archivedArtifactRefs.first {
            $0.artifactID == "planning-numeric-repair-loop-iteration-1-parameter-candidates"
        })
        let archivedBytesBefore = try await store.read(from: archivedCandidates.path)

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "run-numeric-repair-loop",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--max-candidates",
                "5",
                "--max-iterations",
                "3",
                "--pretty",
            ])
            Issue.record("Expected rerun to reject existing numeric repair loop archive artifact.")
        } catch let error as XcircuiteNumericRepairLoopError {
            #expect(error == .archiveArtifactAlreadyExists(path: archivedCandidates.path))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let archivedBytesAfter = try await store.read(from: archivedCandidates.path)
        #expect(archivedBytesAfter == archivedBytesBefore)
    }

    private func makeNumericRepairProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-numeric-repair-problem",
            runID: runID,
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "simulation-summary",
                    kind: "simulation-metric-report",
                    path: ".xcircuite/runs/\(runID)/planning/verification/simulation-metric/simulation-summary.json",
                    artifactID: "planning-simulation-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/rc.cir"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "metric-vfinal",
                    kind: "improve",
                    domain: "simulation",
                    priority: "error",
                    sourceRefIDs: ["simulation-summary"],
                    target: "measurement-within-tolerance",
                    currentValue: .scalar(1.0),
                    requiredValue: .scalar(0.889),
                    description: "Recover simulation metric by bounded parameter search."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "metric-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "Candidate parameters must pass simulation metrics.",
                    sourceRefIDs: ["simulation-summary"]
                ),
            ],
            actionDomainRefs: ["simulation-analysis"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "metric-search-1",
                    domainID: "simulation-analysis",
                    operationID: "metric-driven-parameter-search",
                    maturity: "implemented",
                    reason: "Search bounded parameter candidates before creating concrete edit plans.",
                    sourceObjectiveIDs: ["metric-vfinal"],
                    requiredInputRefs: ["source-netlist-ref"],
                    verificationGates: ["simulation-metric-gate"],
                    parameterHints: [
                        "parameterBounds": .parameterBounds([
                            XcircuiteParameterBound(
                                name: "R1",
                                lowerBound: 500,
                                upperBound: 1500,
                                nominalValue: 1000,
                                step: 250,
                                unit: "ohm"
                            ),
                        ]),
                        "simulationInputs": .simulationInputs(
                            PlanningSimulationInputs(
                                netlistReferenceID: "source-netlist-ref",
                                measurementExpectations: [
                                    SimulationMeasurementExpectation(
                                        name: "vfinal",
                                        target: 0.889,
                                        tolerance: 0.02
                                    ),
                                ]
                            )
                        ),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-distance-from-nominal", terms: [
                XcircuitePlanningCostTerm(
                    termID: "parameter-distance",
                    weight: 1,
                    direction: "minimize",
                    description: "Prefer candidates closer to nominal parameter values."
                ),
            ]),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Candidate parameters must satisfy simulation metrics."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: [
                    "planning/problem.json",
                    "planning/parameter-candidates.jsonl",
                    "planning/parameter-candidate-search-trace.json",
                    "planning/numeric-repair-loop.json",
                ],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func writeText(_ text: String, path: String, root: URL) async throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readJSONLines<T: Decodable>(
        _ type: T.Type,
        from relativePath: String,
        store: XcircuiteWorkspaceStore
    ) async throws -> [T] {
        let data = try await store.read(from: relativePath)
        let text = try #require(String(data: data, encoding: .utf8))
        return try text.split(separator: "\n").map { line in
            try JSONDecoder().decode(T.self, from: Data(String(line).utf8))
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteNumericRepairLoopRunnerTests-\(name)-\(UUID().uuidString)")
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
}
