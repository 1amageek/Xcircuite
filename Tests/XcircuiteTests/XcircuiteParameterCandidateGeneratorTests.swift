import CircuiteFoundation
import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite parameter candidate generator")
struct XcircuiteParameterCandidateGeneratorTests {
    @Test func generateParameterCandidatesCLIWritesJSONLAndRunArtifact() async throws {
        let root = try makeTemporaryRoot("parameter-candidates-cli")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-1", store: store)
        _ = try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-1", withBounds: true),
            runID: "run-1",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "generate-parameter-candidates",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--max-candidates",
            "3",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteParameterCandidateGenerationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        #expect(result.candidateCount == 3)
        let artifact = try #require(result.parameterCandidatesArtifact)
        let searchTraceArtifact = try #require(result.searchTraceArtifact)
        #expect(artifact.artifactID == XcircuitePlanningArtifactStore.parameterCandidatesArtifactID)
        #expect(artifact.path == ".xcircuite/runs/run-1/planning/parameter-candidates.jsonl")
        #expect(!artifact.digest.hexadecimalValue.isEmpty)
        #expect(artifact.byteCount > 0)
        #expect(searchTraceArtifact.artifactID == XcircuitePlanningArtifactStore.parameterCandidateSearchTraceArtifactID)
        #expect(searchTraceArtifact.path == ".xcircuite/runs/run-1/planning/parameter-candidate-search-trace.json")

        let candidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: artifact.path,
            store: store
        )
        #expect(candidates.map(\.rank) == [1, 2, 3])
        #expect(candidates.allSatisfy { $0.sourceActionID == "metric-search-1" })
        #expect(candidates.allSatisfy { $0.verificationGates.contains("simulation-metric-gate") })
        let values = candidates.flatMap(\.assignments)
            .filter { $0.name == "R1" }
            .map(\.value)
        #expect(values.contains(1000))
        #expect(values.contains(500))
        #expect(values.contains(1500))

        let ledger = try await store.loadRunLedger(runID: "run-1")
        #expect(ledger.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.parameterCandidatesArtifactID
                && $0.digest == artifact.digest
                && artifact.byteCount == $0.byteCount
        })
        #expect(ledger.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.parameterCandidateSearchTraceArtifactID
                && $0.digest == searchTraceArtifact.digest
                && searchTraceArtifact.byteCount == $0.byteCount
        })
    }

    @Test func adaptiveBoundedRefinementUsesPreferredDirectionAndWritesSearchTrace() async throws {
        let root = try makeTemporaryRoot("adaptive-parameter-candidates")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-3", store: store)
        _ = try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-3", withBounds: true, preferredDirection: "increase"),
            runID: "run-3",
            projectRoot: root
        )

        let result = try await XcircuiteParameterCandidateGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        ).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(
                runID: "run-3",
                strategy: "adaptive-bounded-refinement",
                maxCandidates: 5
            ),
            projectRoot: root
        )

        #expect(result.status == "generated")
        #expect(result.candidateCount == 5)
        let artifact = try #require(result.parameterCandidatesArtifact)
        let candidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: artifact.path,
            store: store
        )
        let values = candidates.compactMap { candidate in
            candidate.assignments.first { $0.name == "R1" }?.value
        }
        #expect(values == [1000, 1250, 750, 1500, 500])

        let traceRef = try #require(result.searchTraceArtifact)
        let trace = try await store.readJSON(
            XcircuiteParameterCandidateSearchTrace.self,
            from: traceRef.path
        )
        #expect(trace.strategy == "adaptive-bounded-refinement")
        #expect(trace.problemPath == ".xcircuite/runs/run-3/planning/problem.json")
        #expect(trace.generatedCandidateIDs == candidates.map(\.candidateID))
        let actionTrace = try #require(trace.actionTraces.first)
        let parameterTrace = try #require(actionTrace.parameterTraces.first { $0.name == "R1" })
        #expect(parameterTrace.preferredDirection == "increase")
        #expect(parameterTrace.generatedValues.map(\.value) == [1000, 1250, 750, 1500, 500])
    }

    @Test func feedbackAwareRefinementDemotesRejectedAssignmentsAndRecordsLearningTrace() async throws {
        let root = try makeTemporaryRoot("feedback-aware-parameter-candidates")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-4", store: store)
        _ = try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-4", withBounds: true, preferredDirection: "increase"),
            runID: "run-4",
            projectRoot: root
        )

        let generator = XcircuiteParameterCandidateGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        )
        let initialResult = try await generator.generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(
                runID: "run-4",
                strategy: "adaptive-bounded-refinement",
                maxCandidates: 5
            ),
            projectRoot: root
        )
        let initialArtifact = try #require(initialResult.parameterCandidatesArtifact)
        let initialCandidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: initialArtifact.path,
            store: store
        )
        let rejectedCandidate = try #require(initialCandidates.first {
            $0.assignments.first { $0.name == "R1" }?.value == 1000
        })
        _ = try await artifactStore.appendRejectedPlan(
            try rejectedPlanRecord(
                runID: "run-4",
                problemID: rejectedCandidate.problemID,
                planID: "run-4-rejected-plan",
                status: "rejected",
                candidateID: rejectedCandidate.candidateID
            ),
            runID: "run-4",
            projectRoot: root
        )

        let learnedResult = try await generator.generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(
                runID: "run-4",
                strategy: "feedback-aware-bounded-refinement",
                maxCandidates: 5
            ),
            projectRoot: root
        )
        let learnedArtifact = try #require(learnedResult.parameterCandidatesArtifact)
        let learnedCandidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: learnedArtifact.path,
            store: store
        )
        let values = learnedCandidates.compactMap { candidate in
            candidate.assignments.first { $0.name == "R1" }?.value
        }
        #expect(values == [1250, 750, 1500, 500, 1000])
        #expect(learnedCandidates.last?.candidateID == rejectedCandidate.candidateID)
        #expect(learnedCandidates.last?.diagnostics.contains {
            $0.code == "feedback-learned-assignment"
        } == true)

        let traceRef = try #require(learnedResult.searchTraceArtifact)
        let trace = try await store.readJSON(
            XcircuiteParameterCandidateSearchTrace.self,
            from: traceRef.path
        )
        let feedbackTrace = try #require(trace.feedbackTrace)
        #expect(feedbackTrace.strategy == "feedback-aware-bounded-refinement")
        #expect(feedbackTrace.recordCount == 1)
        #expect(feedbackTrace.learnedAssignmentCount == 1)
        #expect(feedbackTrace.previousParameterCandidatesPath == ".xcircuite/runs/run-4/planning/parameter-candidates.jsonl")
        #expect(feedbackTrace.unresolvedCandidateIDs.isEmpty)
        let actionTrace = try #require(trace.actionTraces.first)
        let parameterTrace = try #require(actionTrace.parameterTraces.first { $0.name == "R1" })
        let nominalTrace = try #require(parameterTrace.generatedValues.first { $0.value == 1000 })
        #expect(nominalTrace.feedbackCandidateIDs == [rejectedCandidate.candidateID])
        #expect(nominalTrace.feedbackStatuses == ["rejected"])
        #expect((nominalTrace.feedbackPenalty ?? 0) > 0)
    }

    @Test func rejectedPlanLedgerRejectsCorruptedExistingJSONL() async throws {
        let root = try makeTemporaryRoot("rejected-plan-ledger-corruption")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-ledger-corrupt", store: store)
        let ledgerPath = ".xcircuite/runs/run-ledger-corrupt/planning/rejected-plans.jsonl"
        try await store.writeWorkspaceText("{not-json}\n", to: ledgerPath)

        let record = try rejectedPlanRecord(
            runID: "run-ledger-corrupt",
            problemID: "problem-ledger-corrupt",
            planID: "plan-ledger-corrupt",
            status: "rejected",
            candidateID: "candidate-ledger-corrupt"
        )
        do {
            _ = try await artifactStore.appendRejectedPlan(
                record,
                runID: "run-ledger-corrupt",
                projectRoot: root
            )
            Issue.record("Expected rejected-plan ledger corruption to block append.")
        } catch let error as XcircuitePlanningArtifactError {
            guard case .invalidJSONLLine(let path, let line, _) = error else {
                Issue.record("Unexpected planning artifact error: \(error)")
                return
            }
            #expect(path == ledgerPath)
            #expect(line == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func rejectedPlanLedgerRejectsDuplicateRejectionID() async throws {
        let root = try makeTemporaryRoot("rejected-plan-ledger-duplicate")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-ledger-duplicate", store: store)
        let record = try rejectedPlanRecord(
            runID: "run-ledger-duplicate",
            problemID: "problem-ledger-duplicate",
            planID: "plan-ledger-duplicate",
            status: "rejected",
            candidateID: "candidate-ledger-duplicate"
        )
        _ = try await artifactStore.appendRejectedPlan(
            record,
            runID: "run-ledger-duplicate",
            projectRoot: root
        )

        do {
            _ = try await artifactStore.appendRejectedPlan(
                record,
                runID: "run-ledger-duplicate",
                projectRoot: root
            )
            Issue.record("Expected duplicate rejected-plan ledger entry to block append.")
        } catch let error as XcircuitePlanningArtifactError {
            #expect(error == .duplicateRejectedPlan(rejectionID: record.rejectionID))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func calibratedFeedbackAwareRefinementDemotesParetoFailedCandidates() async throws {
        let root = try makeTemporaryRoot("calibrated-feedback-aware-parameter-candidates")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-5", store: store)
        let problem = makeMetricPlanningProblem(runID: "run-5", withBounds: true, preferredDirection: "increase")
        _ = try await artifactStore.persistPlanningProblem(problem, runID: "run-5", projectRoot: root)

        let generator = XcircuiteParameterCandidateGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        )
        let initialResult = try await generator.generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(
                runID: "run-5",
                strategy: "adaptive-bounded-refinement",
                maxCandidates: 5
            ),
            projectRoot: root
        )
        let initialArtifact = try #require(initialResult.parameterCandidatesArtifact)
        let initialCandidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: initialArtifact.path,
            store: store
        )
        let nominalCandidate = try #require(initialCandidates.first {
            $0.assignments.first { $0.name == "R1" }?.value == 1000
        })
        let preferredIncreaseCandidate = try #require(initialCandidates.first {
            $0.assignments.first { $0.name == "R1" }?.value == 1250
        })

        _ = try await artifactStore.persistMetricThresholdProfile(
            XcircuiteMetricThresholdProfile(
                runID: "run-5",
                problemID: problem.problemID,
                profileID: "run-5-threshold-profile",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholds: [
                    XcircuiteMetricThresholdProfile.Threshold(
                        metricID: "metric-vfinal",
                        objectiveID: "metric-vfinal",
                        domain: "simulation",
                        metricName: "vfinal",
                        direction: "within-tolerance",
                        targetValue: 1.0,
                        severity: "error",
                        sourceRefIDs: ["simulation-summary"]
                    ),
                ]
            ),
            runID: "run-5",
            projectRoot: root
        )
        _ = try await artifactStore.persistCostCalibrationReport(
            XcircuiteCostCalibrationReport(
                runID: "run-5",
                problemID: problem.problemID,
                calibrationID: "run-5-cost-calibration",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                inputArtifactIDs: [XcircuitePlanningArtifactStore.parameterCandidatesArtifactID],
                calibratedTerms: [
                    XcircuiteCostCalibrationReport.Term(
                        termID: "feedback.gate.simulation-metric-gate",
                        gateID: "simulation-metric-gate",
                        baseWeight: 1,
                        calibratedWeight: 2,
                        evidenceCount: 2,
                        rationale: "Failed simulation metric gates should be demoted in subsequent numeric search."
                    ),
                ],
                observations: [
                    XcircuiteCostCalibrationReport.Observation(
                        candidateID: nominalCandidate.candidateID,
                        accepted: false,
                        selectedTotalScore: 0,
                        failedGateIDs: ["simulation-metric-gate"],
                        sourceArtifactIDs: [XcircuitePlanningArtifactStore.parameterCandidatesArtifactID]
                    ),
                    XcircuiteCostCalibrationReport.Observation(
                        candidateID: preferredIncreaseCandidate.candidateID,
                        accepted: false,
                        selectedTotalScore: 0.25,
                        failedGateIDs: ["simulation-metric-gate"],
                        sourceArtifactIDs: [XcircuitePlanningArtifactStore.parameterCandidatesArtifactID]
                    ),
                ]
            ),
            runID: "run-5",
            projectRoot: root
        )
        _ = try await artifactStore.persistParetoCandidates(
            XcircuiteParetoCandidateSet(
                runID: "run-5",
                problemID: problem.problemID,
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                costCalibrationArtifactID: XcircuitePlanningArtifactStore.costCalibrationArtifactID,
                sourceCandidateArtifactIDs: [XcircuitePlanningArtifactStore.parameterCandidatesArtifactID],
                candidates: [
                    XcircuiteParetoCandidateSet.Candidate(
                        runID: "run-5",
                        problemID: problem.problemID,
                        generatedAt: "2026-06-23T00:00:00Z",
                        candidateID: "iteration-1-\(nominalCandidate.candidateID)",
                        sourceCandidateID: nominalCandidate.candidateID,
                        frontierRank: 3,
                        dominatedByCandidateIDs: ["iteration-1-\(preferredIncreaseCandidate.candidateID)"],
                        metrics: [],
                        gateStatuses: ["simulation-metric-gate": "failed"],
                        rationale: "Nominal candidate failed simulation metric gate."
                    ),
                    XcircuiteParetoCandidateSet.Candidate(
                        runID: "run-5",
                        problemID: problem.problemID,
                        generatedAt: "2026-06-23T00:00:00Z",
                        candidateID: "iteration-1-\(preferredIncreaseCandidate.candidateID)",
                        sourceCandidateID: preferredIncreaseCandidate.candidateID,
                        frontierRank: 2,
                        dominatedByCandidateIDs: [],
                        metrics: [],
                        gateStatuses: ["simulation-metric-gate": "failed"],
                        rationale: "Preferred increase candidate failed simulation metric gate."
                    ),
                ]
            ),
            runID: "run-5",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "generate-parameter-candidates",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-5",
            "--strategy",
            "calibrated-feedback-aware-bounded-refinement",
            "--max-candidates",
            "5",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteParameterCandidateGenerationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        let calibratedArtifact = try #require(result.parameterCandidatesArtifact)
        let calibratedCandidates = try await readJSONLines(
            XcircuiteParameterCandidate.self,
            from: calibratedArtifact.path,
            store: store
        )
        let values = calibratedCandidates.compactMap { candidate in
            candidate.assignments.first { $0.name == "R1" }?.value
        }
        #expect(values == [750, 1500, 500, 1250, 1000])
        #expect(calibratedCandidates.last?.candidateID == nominalCandidate.candidateID)
        #expect(calibratedCandidates.last?.diagnostics.contains {
            $0.code == "cp7-calibration-penalty"
        } == true)

        let traceRef = try #require(result.searchTraceArtifact)
        let trace = try await store.readJSON(
            XcircuiteParameterCandidateSearchTrace.self,
            from: traceRef.path
        )
        let calibrationTrace = try #require(trace.calibrationTrace)
        #expect(calibrationTrace.strategy == "calibrated-feedback-aware-bounded-refinement")
        #expect(calibrationTrace.thresholdCount == 1)
        #expect(calibrationTrace.calibratedTermCount == 1)
        #expect(calibrationTrace.paretoCandidateCount == 2)
        #expect(calibrationTrace.appliedCandidateCount == 5)
        #expect(calibrationTrace.matchedSourceCandidateIDs.contains(nominalCandidate.candidateID))
        #expect(calibrationTrace.matchedSourceCandidateIDs.contains(preferredIncreaseCandidate.candidateID))
        #expect(calibrationTrace.matchedGateIDs == ["simulation-metric-gate"])
    }

    @Test func missingBoundsBlocksGenerationWithoutCandidateArtifact() async throws {
        let root = try makeTemporaryRoot("parameter-candidates-missing-bounds")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-2", store: store)
        _ = try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-2", withBounds: false),
            runID: "run-2",
            projectRoot: root
        )

        let result = try await XcircuiteParameterCandidateGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        ).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-2"),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.candidateCount == 0)
        #expect(result.parameterCandidatesArtifact == nil)
        let traceRef = try #require(result.searchTraceArtifact)
        #expect(traceRef.artifactID == XcircuitePlanningArtifactStore.parameterCandidateSearchTraceArtifactID)
        let trace = try await store.readJSON(
            XcircuiteParameterCandidateSearchTrace.self,
            from: traceRef.path
        )
        #expect(trace.generatedCandidateCount == 0)
        #expect(trace.generatedCandidateIDs.isEmpty)
        #expect(trace.diagnostics.contains { $0.code == "no-bounded-parameter-actions" })
        #expect(result.diagnostics.contains { $0.code == "no-bounded-parameter-actions" })
    }

    @Test func generateParameterCandidatesRejectsTamperedPlanningProblemManifestArtifactBeforeUse() async throws {
        let root = try makeTemporaryRoot("parameter-candidates-tampered-problem")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareTestRun(runID: "run-tampered-problem", store: store)
        let problemReference = try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-tampered-problem", withBounds: true),
            runID: "run-tampered-problem",
            projectRoot: root
        )
        try await store.write(Data(#"{"tampered":true}"#.utf8), to: problemReference.path)

        do {
            _ = try await XcircuiteParameterCandidateGenerator(
                workspaceStore: store,
                artifactStore: artifactStore
            ).generateParameterCandidates(
                request: XcircuiteParameterCandidateGenerationRequest(runID: "run-tampered-problem"),
                projectRoot: root
            )
            Issue.record("Expected tampered planning problem artifact to fail integrity verification.")
        } catch let error as XcircuiteParameterCandidateGenerationError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected parameter candidate generation error: \(error)")
                return
            }
            #expect(path == problemReference.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    private func makeMetricPlanningProblem(
        runID: String,
        withBounds: Bool,
        preferredDirection: String? = nil
    ) -> XcircuiteCircuitPlanningProblem {
        var parameterHints: [String: PlanningParameterValue] = [
            "metric": .text("vfinal"),
        ]
        if withBounds {
            parameterHints["parameterBounds"] = .parameterBounds([
                XcircuiteParameterBound(
                    name: "R1",
                    lowerBound: 500,
                    upperBound: 1500,
                    nominalValue: 1000,
                    step: 250,
                    unit: "ohm",
                    preferredDirection: preferredDirection
                ),
            ])
        }
        return XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-metric-improvement-problem",
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
                    currentValue: .scalar(0.5),
                    requiredValue: .scalar(1.0),
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
                    parameterHints: parameterHints
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
                ],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func rejectedPlanRecord(
        runID: String,
        problemID: String,
        planID: String,
        status: String,
        candidateID: String
    ) throws -> XcircuiteRejectedPlanRecord {
        XcircuiteRejectedPlanRecord(
            rejectionID: "\(planID)-\(status)",
            runID: runID,
            problemID: problemID,
            planID: planID,
            verificationMode: "post-execution",
            status: status,
            sourceParameterCandidateIDs: [candidateID],
            failedStepIDs: [],
            failedGateIDs: ["simulation-metric-gate"],
            candidatePlanRef: try fixtureArtifactReference(
                artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                path: ".xcircuite/runs/\(runID)/planning/candidate-plan.json",
                kind: .other,
                format: .json
            ),
            planVerificationRef: try fixtureArtifactReference(
                artifactID: XcircuitePlanningArtifactStore.planVerificationArtifactID,
                path: ".xcircuite/runs/\(runID)/planning/plan-verification.json",
                kind: .other,
                format: .json
            ),
            artifactRefs: [],
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                    message: "Candidate measurement missed target.",
                    gateID: "simulation-metric-gate"
                ),
            ],
            nextActions: ["repair-verification-gate:simulation-metric-gate"]
        )
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
            .appending(path: "XcircuiteParameterCandidateGeneratorTests-\(name)-\(UUID().uuidString)")
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
