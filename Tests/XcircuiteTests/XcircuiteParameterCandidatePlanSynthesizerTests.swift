import Foundation
import CircuiteFoundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite parameter candidate plan synthesizer")
struct XcircuiteParameterCandidatePlanSynthesizerTests {
    @Test func synthesizeParameterCandidatePlanCLIAndExecuteNetlistEdit() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-synthesis")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-1", store: store)
        try writeTextFixture(
            """
            RC Candidate Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-1", withBounds: true),
            runID: "run-1",
            projectRoot: root
        )
        _ = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-1", maxCandidates: 3),
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "synthesize-parameter-candidate-plan",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--rank",
            "2",
            "--pretty",
        ])
        let synthesis = try JSONDecoder().decode(
            XcircuiteParameterCandidatePlanSynthesisResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(synthesis.status == "generated")
        #expect(synthesis.executionReadiness == "ready")
        #expect(synthesis.selectedCandidateRank == 2)
        let selectionTraceRef = try #require(synthesis.selectionTraceArtifact)
        let persistedSelectionTrace = try await store.readJSON(
            XcircuiteParameterCandidateSelectionTrace.self,
            from: selectionTraceRef.path
        )
        #expect(persistedSelectionTrace.selectedCandidateID == synthesis.selectedCandidateID)
        #expect(persistedSelectionTrace.parameterCandidatesPath == synthesis.parameterCandidatesPath)

        let plan = try await store.readJSON(
            XcircuiteCandidatePlan.self,
            from: synthesis.candidatePlanArtifact.path
        )
        #expect(plan.assumptions.map(\.assumptionID) == ["simulation-metric-current"])
        #expect(plan.riskClassifications.map(\.riskID) == ["metric-recovery-regression-risk"])
        let step = try #require(plan.steps.first)
        #expect(step.operationID == "simulation.set-netlist-parameters")
        #expect(step.parameterHints["netlistPath"] == .text("circuits/rc.spice"))
        #expect(step.parameterHints["sourceParameterCandidateID"] == .text(synthesis.selectedCandidateID))

        let execution = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-1"),
            projectRoot: root
        )

        #expect(execution.status == "executed")
        let netlistRef = try #require(execution.producedArtifacts.first {
            $0.artifactID == "candidate-step-1-edited-netlist"
        })
        let editedNetlist = try String(contentsOf: root.appending(path: netlistRef.path), encoding: .utf8)
        #expect(editedNetlist.contains("r=1.5k"))

        let reportRef = try #require(execution.producedArtifacts.first {
            $0.artifactID == "candidate-step-1-netlist-parameter-edit-report"
        })
        let report = try await store.readJSON(
            XcircuiteNetlistParameterEditReport.self,
            from: reportRef.path
        )
        #expect(report.sourceParameterCandidateID == synthesis.selectedCandidateID)
        #expect(report.outputNetlistPath == netlistRef.path)
        #expect(report.edits.first?.assignmentName == "R1")
        #expect(report.edits.first?.targetKind == "component-parameter")
        #expect(report.edits.first?.targetName == "r1")
        #expect(report.edits.first?.parameterName == "r")
        #expect(report.edits.first?.value == 1500)

        let ledger = try await store.loadRunLedger(runID: "run-1")
        #expect(ledger.artifacts.contains { $0.id.rawValue == XcircuitePlanningArtifactStore.candidatePlanArtifactID })
        #expect(ledger.artifacts.contains {
            $0.id.rawValue == XcircuitePlanningArtifactStore.parameterCandidateSelectionTraceArtifactID
        })
        #expect(ledger.artifacts.contains { $0.id.rawValue == "candidate-step-1-edited-netlist" })
        #expect(ledger.artifacts.contains { $0.id.rawValue == "candidate-step-1-netlist-parameter-edit-report" })
    }

    @Test func missingCandidateRankFailsWithoutReplacingCandidatePlan() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-missing-rank")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-2", store: store)
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-2", withBounds: true),
            runID: "run-2",
            projectRoot: root
        )
        _ = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-2", maxCandidates: 2),
            projectRoot: root
        )

        do {
            _ = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
                request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-2", rank: 9),
                projectRoot: root
            )
            Issue.record("Expected missing candidate rank error")
        } catch let error as XcircuiteParameterCandidatePlanSynthesisError {
            #expect(error == .candidateNotFound(candidateID: nil, rank: 9))
        }

        let ledger = try await store.loadRunLedger(runID: "run-2")
        #expect(!ledger.artifacts.contains {
            $0.id.rawValue == XcircuitePlanningArtifactStore.candidatePlanArtifactID
        })
    }

    @Test func synthesisRejectsStaleParameterCandidatesArtifact() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-stale-candidates")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-stale", store: store)
        try writeTextFixture(
            """
            RC Stale Candidate Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-stale", withBounds: true),
            runID: "run-stale",
            projectRoot: root
        )
        let generation = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-stale", maxCandidates: 2),
            projectRoot: root
        )
        let candidatesArtifact = try #require(generation.parameterCandidatesArtifact)
        let candidatesURL = root.appending(path: candidatesArtifact.path)
        let original = try String(contentsOf: candidatesURL, encoding: .utf8)
        let firstLine = try #require(original.split(separator: "\n").first)
        try "\(original)\n\(firstLine)\n".write(to: candidatesURL, atomically: true, encoding: .utf8)

        do {
            _ = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
                request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-stale", rank: 1),
                projectRoot: root
            )
            Issue.record("Expected stale parameter candidates artifact rejection")
        } catch let error as XcircuiteParameterCandidatePlanSynthesisError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected synthesis error: \(error)")
                return
            }
            #expect(path == candidatesArtifact.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func synthesisSkipsRejectedCandidateFeedbackUnlessExplicitlyIncluded() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-feedback")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-3", store: store)
        try writeTextFixture(
            """
            RC Candidate Feedback Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-3", withBounds: true),
            runID: "run-3",
            projectRoot: root
        )
        let candidatesResult = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-3", maxCandidates: 3),
            projectRoot: root
        )
        let candidatesArtifact = try #require(candidatesResult.parameterCandidatesArtifact)
        let candidates = try readJSONLines(
            XcircuiteParameterCandidate.self,
            from: root.appending(path: candidatesArtifact.path)
        )
        let rejectedCandidate = try #require(candidates.first { $0.rank == 1 })
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-3",
                problemID: rejectedCandidate.problemID,
                planID: "run-3-rejected-plan",
                status: "rejected",
                candidateID: rejectedCandidate.candidateID
            ),
            runID: "run-3",
            projectRoot: root
        )

        let synthesis = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-3"),
            projectRoot: root
        )

        #expect(synthesis.selectedCandidateID != rejectedCandidate.candidateID)
        #expect(synthesis.skippedRejectedCandidateIDs == [rejectedCandidate.candidateID])
        #expect(synthesis.rejectedPlanFeedback?.excludedCandidateIDs == [rejectedCandidate.candidateID])
        let trace = try #require(synthesis.selectionTrace)
        #expect(trace.selectedCandidateID == synthesis.selectedCandidateID)
        #expect(trace.runID == "run-3")
        #expect(trace.problemID == rejectedCandidate.problemID)
        #expect(trace.rejectedPlansPath == ".xcircuite/runs/run-3/planning/rejected-plans.jsonl")
        let rejectedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == rejectedCandidate.candidateID
        })
        #expect(rejectedScore.selectionState == "excluded")
        #expect(rejectedScore.exclusionReason == "rejected-feedback")
        #expect(rejectedScore.feedbackPenalty > 0)

        do {
            _ = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
                request: XcircuiteParameterCandidatePlanSynthesisRequest(
                    runID: "run-3",
                    candidateID: rejectedCandidate.candidateID
                ),
                projectRoot: root
            )
            Issue.record("Expected rejected candidate feedback error")
        } catch let error as XcircuiteParameterCandidatePlanSynthesisError {
            #expect(error == .candidateRejectedByFeedback(
                candidateID: rejectedCandidate.candidateID,
                statuses: ["rejected"],
                failedGateIDs: ["simulation-metric-gate"]
            ))
        }

        let retryJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "synthesize-parameter-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-3",
                "--candidate-id",
                rejectedCandidate.candidateID,
                "--include-rejected-candidates",
                "--pretty",
            ]
        )
        let retry = try JSONDecoder().decode(
            XcircuiteParameterCandidatePlanSynthesisResult.self,
            from: try #require(retryJSON.data(using: .utf8))
        )
        #expect(retry.selectedCandidateID == rejectedCandidate.candidateID)
        #expect(retry.rejectedPlanFeedback?.excludedCandidateIDs == [rejectedCandidate.candidateID])
    }

    @Test func synthesisDoesNotExcludeBlockedCandidateFeedback() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-blocked-feedback")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-4", store: store)
        try writeTextFixture(
            """
            RC Candidate Blocked Feedback Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-4", withBounds: true),
            runID: "run-4",
            projectRoot: root
        )
        let candidatesResult = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-4", maxCandidates: 3),
            projectRoot: root
        )
        let candidatesArtifact = try #require(candidatesResult.parameterCandidatesArtifact)
        let candidates = try readJSONLines(
            XcircuiteParameterCandidate.self,
            from: root.appending(path: candidatesArtifact.path)
        )
        let blockedCandidate = try #require(candidates.first { $0.rank == 1 })
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-4",
                problemID: blockedCandidate.problemID,
                planID: "run-4-blocked-plan",
                status: "blocked",
                candidateID: blockedCandidate.candidateID
            ),
            runID: "run-4",
            projectRoot: root
        )

        let synthesis = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-4"),
            projectRoot: root
        )

        #expect(synthesis.selectedCandidateID == blockedCandidate.candidateID)
        #expect(synthesis.skippedRejectedCandidateIDs == nil)
        #expect(synthesis.rejectedPlanFeedback?.excludedCandidateIDs == [])
        let trace = try #require(synthesis.selectionTrace)
        let traceRef = try #require(synthesis.selectionTraceArtifact)
        let persistedTrace = try await store.readJSON(
            XcircuiteParameterCandidateSelectionTrace.self,
            from: traceRef.path
        )
        #expect(persistedTrace.selectedCandidateID == trace.selectedCandidateID)
        let blockedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == blockedCandidate.candidateID
        })
        #expect(blockedScore.selectionState == "selected")
        #expect(blockedScore.feedbackPenalty > 0)
        #expect(blockedScore.totalScore > blockedScore.baseCost)
    }

    @Test func synthesisRanksEligibleCandidatesWithFeedbackPenalty() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-feedback-ranking")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-5", store: store)
        try writeTextFixture(
            """
            RC Candidate Feedback Ranking Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(runID: "run-5", withBounds: true),
            runID: "run-5",
            projectRoot: root
        )
        let candidatesResult = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-5", maxCandidates: 3),
            projectRoot: root
        )
        let candidatesArtifact = try #require(candidatesResult.parameterCandidatesArtifact)
        let candidates = try readJSONLines(
            XcircuiteParameterCandidate.self,
            from: root.appending(path: candidatesArtifact.path)
        )
        let rejectedCandidate = try #require(candidates.first { $0.rank == 1 })
        let blockedCandidate = try #require(candidates.first { $0.rank == 2 })
        let cleanCandidate = try #require(candidates.first { $0.rank == 3 })
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-5",
                problemID: rejectedCandidate.problemID,
                planID: "run-5-rejected-plan",
                status: "rejected",
                candidateID: rejectedCandidate.candidateID
            ),
            runID: "run-5",
            projectRoot: root
        )
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-5",
                problemID: blockedCandidate.problemID,
                planID: "run-5-blocked-plan",
                status: "blocked",
                candidateID: blockedCandidate.candidateID
            ),
            runID: "run-5",
            projectRoot: root
        )

        let synthesis = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-5"),
            projectRoot: root
        )

        #expect(synthesis.selectedCandidateID == cleanCandidate.candidateID)
        #expect(synthesis.skippedRejectedCandidateIDs == [rejectedCandidate.candidateID])
        let trace = try #require(synthesis.selectionTrace)
        #expect(trace.selectedCandidateID == cleanCandidate.candidateID)
        let selectedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == cleanCandidate.candidateID
        })
        let blockedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == blockedCandidate.candidateID
        })
        let rejectedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == rejectedCandidate.candidateID
        })
        #expect(selectedScore.selectionState == "selected")
        #expect(blockedScore.selectionState == "eligible")
        #expect(rejectedScore.selectionState == "excluded")
        #expect(blockedScore.feedbackPenalty > 0)
        #expect(selectedScore.totalScore < blockedScore.totalScore)
    }

    @Test func synthesisUsesCostModelFeedbackWeightingPolicy() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-feedback-weighting")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-6", store: store)
        try writeTextFixture(
            """
            RC Candidate Feedback Weighting Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        let feedbackTerms = [
            feedbackCostTerm("feedback.blocked", 0),
            feedbackCostTerm("feedback.failed-gate", 0),
            feedbackCostTerm("feedback.diagnostic", 0),
            feedbackCostTerm("feedback.next-action", 0),
        ]
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(
                runID: "run-6",
                withBounds: true,
                feedbackCostTerms: feedbackTerms
            ),
            runID: "run-6",
            projectRoot: root
        )
        let candidatesResult = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-6", maxCandidates: 3),
            projectRoot: root
        )
        let candidatesArtifact = try #require(candidatesResult.parameterCandidatesArtifact)
        let candidates = try readJSONLines(
            XcircuiteParameterCandidate.self,
            from: root.appending(path: candidatesArtifact.path)
        )
        let rejectedCandidate = try #require(candidates.first { $0.rank == 1 })
        let blockedCandidate = try #require(candidates.first { $0.rank == 2 })
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-6",
                problemID: rejectedCandidate.problemID,
                planID: "run-6-rejected-plan",
                status: "rejected",
                candidateID: rejectedCandidate.candidateID
            ),
            runID: "run-6",
            projectRoot: root
        )
        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-6",
                problemID: blockedCandidate.problemID,
                planID: "run-6-blocked-plan",
                status: "blocked",
                candidateID: blockedCandidate.candidateID
            ),
            runID: "run-6",
            projectRoot: root
        )

        let synthesis = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-6"),
            projectRoot: root
        )

        #expect(synthesis.selectedCandidateID == blockedCandidate.candidateID)
        let trace = try #require(synthesis.selectionTrace)
        #expect(trace.feedbackWeighting.source == "planning-cost-model")
        #expect(trace.feedbackWeighting.sourceTermIDs == feedbackTerms.map(\.termID))
        #expect(trace.feedbackWeighting.blockedPenalty == 0)
        let blockedScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == blockedCandidate.candidateID
        })
        #expect(blockedScore.feedbackPenalty == 0)
        let blockedComponent = try #require(blockedScore.feedbackPenaltyComponents.first {
            $0.componentID == "feedback.blocked"
        })
        #expect(blockedComponent.unitPenalty == 0)
        #expect(blockedComponent.appliedPenalty == 0)
    }

    @Test func synthesisAppliesGlobalRejectedPlanFeedbackToMatchingVerificationGate() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-global-feedback")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-8", store: store)
        try writeTextFixture(
            """
            RC Global Feedback Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        let problem = makeMultiGateParameterPlanningProblem(runID: "run-8")
        try await artifactStore.persistPlanningProblem(
            problem,
            runID: "run-8",
            projectRoot: root
        )
        let candidatesResult = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-8", maxCandidates: 4),
            projectRoot: root
        )
        let candidatesArtifact = try #require(candidatesResult.parameterCandidatesArtifact)
        let candidates = try readJSONLines(
            XcircuiteParameterCandidate.self,
            from: root.appending(path: candidatesArtifact.path)
        )
        let drcCandidate = try #require(candidates.first {
            $0.sourceActionID == "a-drc-parameter-search" && $0.normalizedCost == 0
        })
        let simulationCandidate = try #require(candidates.first {
            $0.sourceActionID == "b-simulation-parameter-search" && $0.normalizedCost == 0
        })
        #expect(drcCandidate.rank < simulationCandidate.rank)

        try await artifactStore.appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-8",
                problemID: problem.problemID,
                planID: "run-8-post-waiver-drc-feedback",
                status: "rejected",
                failedGateIDs: ["post-waiver-edit-drc"]
            ),
            runID: "run-8",
            projectRoot: root
        )

        let synthesis = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
            request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-8"),
            projectRoot: root
        )

        #expect(synthesis.selectedCandidateID == simulationCandidate.candidateID)
        #expect(synthesis.skippedRejectedCandidateIDs == nil)
        #expect(synthesis.rejectedPlanFeedback?.candidateFeedback == [])
        #expect(synthesis.rejectedPlanFeedback?.globalFeedback.count == 1)
        #expect(synthesis.rejectedPlanFeedback?.globalFeedback.first?.failedGateIDs == ["post-waiver-edit-drc"])

        let trace = try #require(synthesis.selectionTrace)
        let drcScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == drcCandidate.candidateID
        })
        let simulationScore = try #require(trace.rankedCandidates.first {
            $0.candidateID == simulationCandidate.candidateID
        })
        #expect(drcScore.selectionState == "eligible")
        #expect(drcScore.feedbackPenalty > 0)
        #expect(drcScore.failedGateIDs == ["post-waiver-edit-drc"])
        #expect(drcScore.feedbackPenaltyComponents.contains {
            $0.componentID == "feedback.global.failed-gate"
        })
        #expect(simulationScore.selectionState == "selected")
        #expect(simulationScore.feedbackPenalty == 0)
    }

    @Test func synthesisRejectsInvalidFeedbackWeightingPolicy() async throws {
        let root = try makeTemporaryRoot("parameter-candidate-plan-invalid-feedback-weighting")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-7", store: store)
        try writeTextFixture(
            """
            RC Invalid Feedback Weighting Test
            R1 in out 1k
            C1 out 0 1u
            .tran 1u 10u
            .end
            """,
            to: root.appending(path: "circuits/rc.spice")
        )
        try await artifactStore.persistPlanningProblem(
            makeMetricPlanningProblem(
                runID: "run-7",
                withBounds: true,
                feedbackCostTerms: [
                    feedbackCostTerm("feedback.blocked", -1),
                ]
            ),
            runID: "run-7",
            projectRoot: root
        )
        _ = try await XcircuiteParameterCandidateGenerator(workspaceStore: store, artifactStore: artifactStore).generateParameterCandidates(
            request: XcircuiteParameterCandidateGenerationRequest(runID: "run-7", maxCandidates: 2),
            projectRoot: root
        )

        do {
            _ = try await XcircuiteParameterCandidatePlanSynthesizer(workspaceStore: store, artifactStore: artifactStore).synthesizeCandidatePlan(
                request: XcircuiteParameterCandidatePlanSynthesisRequest(runID: "run-7"),
                projectRoot: root
            )
            Issue.record("Expected invalid feedback weighting error")
        } catch let error as XcircuiteParameterCandidatePlanSynthesisError {
            #expect(error == .invalidFeedbackWeight(termID: "feedback.blocked", weight: -1))
        }
    }

    private func makeMetricPlanningProblem(
        runID: String,
        withBounds: Bool,
        feedbackCostTerms: [XcircuitePlanningCostTerm] = []
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
                    unit: "ohm"
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
                    path: "circuits/rc.spice"
                ),
            ],
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "simulation-metric-current",
                    source: "test",
                    statement: "The simulation metric report describes the current failing state.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["simulation-summary"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "metric-recovery-regression-risk",
                    category: "simulation-regression",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Metric recovery candidates can improve one measurement while degrading another.",
                    affectedObjectiveIDs: ["metric-vfinal"],
                    mitigationActions: ["simulation-metric-gate"]
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
            ] + feedbackCostTerms),
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
                    "planning/candidate-plan.json",
                ],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeMultiGateParameterPlanningProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-multi-gate-parameter-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/rc.spice"
                ),
            ],
            assumptions: [],
            riskClassifications: [],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "native-drc-clean",
                    kind: "repair",
                    domain: "layout",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "drc-clean",
                    currentValue: .text("failing"),
                    requiredValue: .text("passing"),
                    description: "Repair native DRC feedback."
                ),
                XcircuitePlanningObjective(
                    objectiveID: "metric-vfinal",
                    kind: "improve",
                    domain: "simulation",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "measurement-within-tolerance",
                    currentValue: .scalar(0.5),
                    requiredValue: .scalar(1.0),
                    description: "Recover simulation metric."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["layout-edit", "simulation-analysis"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "a-drc-parameter-search",
                    domainID: "layout-edit",
                    operationID: "layout.drc-parameter-search",
                    maturity: "implemented",
                    reason: "Search DRC-oriented parameter candidates.",
                    sourceObjectiveIDs: ["native-drc-clean"],
                    requiredInputRefs: ["source-netlist-ref"],
                    verificationGates: ["native-drc"],
                    parameterHints: [
                        "parameterBounds": .parameterBounds([
                            XcircuiteParameterBound(
                                name: "W1",
                                lowerBound: 1,
                                upperBound: 3,
                                nominalValue: 2,
                                step: 1,
                                unit: "um"
                            ),
                        ]),
                    ]
                ),
                XcircuitePlanningCandidateAction(
                    actionID: "b-simulation-parameter-search",
                    domainID: "simulation-analysis",
                    operationID: "simulation.metric-parameter-search",
                    maturity: "implemented",
                    reason: "Search simulation metric parameter candidates.",
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
                    gateID: "native-drc",
                    required: true,
                    description: "Native DRC must pass."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Simulation metrics must pass."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: [
                    "planning/problem.json",
                    "planning/parameter-candidates.jsonl",
                    "planning/candidate-plan.json",
                ],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func feedbackCostTerm(_ termID: String, _ weight: Double) -> XcircuitePlanningCostTerm {
        XcircuitePlanningCostTerm(
            termID: termID,
            weight: weight,
            direction: "minimize",
            description: "Configure feedback-aware parameter candidate selection."
        )
    }

    private func rejectedPlanRecord(
        runID: String,
        problemID: String,
        planID: String,
        status: String,
        candidateID: String? = nil,
        failedGateIDs: [String] = ["simulation-metric-gate"]
    ) throws -> XcircuiteRejectedPlanRecord {
        XcircuiteRejectedPlanRecord(
            rejectionID: "\(planID)-\(status)",
            runID: runID,
            problemID: problemID,
            planID: planID,
            verificationMode: "post-execution",
            status: status,
            sourceParameterCandidateIDs: candidateID.map { [$0] } ?? [],
            failedStepIDs: [],
            failedGateIDs: failedGateIDs,
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
                    gateID: failedGateIDs.first
                ),
            ],
            nextActions: failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                return try decoder.decode(type, from: data)
            }
    }

    private func writeTextFixture(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteParameterCandidatePlanSynthesizerTests-\(name)-\(UUID().uuidString)")
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
