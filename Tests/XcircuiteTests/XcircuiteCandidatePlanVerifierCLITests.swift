import Foundation
import CircuiteFoundation
import LayoutAutoGen
import LayoutCore
import LayoutIO
import LayoutTech
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifierTests {
    @Test func verifyCandidatePlanCLIWritesPlanVerificationAndActionRecord() async throws {
        let root = try makeTemporaryRoot("candidate-plan-verify-cli")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        _ = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        ).generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanVerificationResult.self, from: data)

        #expect(result.status == "blocked")
        #expect(result.accepted == false)
        #expect(result.planVerificationArtifact.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID)
        #expect(result.planVerificationArtifact.path.hasPrefix(
            ".xcircuite/runs/run-1/planning/plan-verification/"
        ))
        #expect(result.planVerificationArtifact.path.hasSuffix(".json"))
        #expect(result.nextActions.contains("bind-operation-input-ref:document-ref"))
        #expect(result.nextActions.contains("bind-operation-input-ref:cell-ref"))
        #expect(result.nextActions.contains("bind-operation-input-ref:layer-ref"))
        #expect(result.nextActions.contains("prove-operation-precondition:cell-exists"))
        #expect(result.nextActions.contains("prove-operation-precondition:unique-shape-id"))
        #expect(result.nextActions.contains("prove-operation-precondition:positive-rect-size"))
        #expect(result.nextActions.contains("unblock-verification-gate:artifact-integrity"))
        #expect(result.nextActions.contains("unblock-verification-gate:native-drc"))
        #expect(result.nextActions.contains("unblock-verification-gate:native-lvs"))

        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.candidatePlanRef.locator.location.value.hasPrefix(
            ".xcircuite/runs/run-1/planning/candidate-plans/"
        ))
        #expect(verification.artifactRefs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        })
        #expect(verification.stepResults.map(\.status) == ["blocked"])
        let symbolicEvaluation = try #require(verification.stepResults.first?.symbolicEvaluation)
        #expect(symbolicEvaluation.actionDomainSupported == true)
        #expect(symbolicEvaluation.operationSupported == true)
        #expect(symbolicEvaluation.operationMaturity == "implemented")
        #expect(symbolicEvaluation.operationReversible == true)
        #expect(symbolicEvaluation.stepRequiredInputRefs == ["layout-ref"])
        #expect(symbolicEvaluation.stepMissingInputRefs == [])
        #expect(symbolicEvaluation.operationInputRefs == [
            "document-ref",
            "cell-ref",
            "layer-ref",
            "optional-net-ref",
        ])
        #expect(symbolicEvaluation.optionalOperationInputRefs == ["optional-net-ref"])
        #expect(symbolicEvaluation.boundOperationInputRefs == [])
        #expect(symbolicEvaluation.unboundOperationInputRefs == [
            "document-ref",
            "cell-ref",
            "layer-ref",
        ])
        #expect(symbolicEvaluation.preconditions == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(symbolicEvaluation.satisfiedPreconditions == [])
        #expect(symbolicEvaluation.unsatisfiedPreconditions == symbolicEvaluation.preconditions)
        #expect(symbolicEvaluation.effects.contains("rect-shape-created"))
        #expect(symbolicEvaluation.appliedEffects.contains("rect-shape-created"))
        #expect(symbolicEvaluation.producedArtifacts.contains("layout-document"))
        #expect(symbolicEvaluation.verificationGates.contains("native-drc"))
        #expect(symbolicEvaluation.stateBefore.contains("ref:planning-problem"))
        #expect(symbolicEvaluation.stateBefore.contains("artifact:planning-problem"))
        #expect(symbolicEvaluation.stateBefore.contains("ref:layout-ref"))
        #expect(symbolicEvaluation.stateAfter.contains("rect-shape-created"))
        #expect(symbolicEvaluation.stateAfter.contains("artifact:layout-document"))
        #expect(symbolicEvaluation.bindingStatus == "partially-bound")
        #expect(verification.diagnostics.contains { $0.code == "unbound-operation-input-refs" })
        #expect(verification.diagnostics.contains { $0.code == "unproven-operation-preconditions" })
        #expect(verification.gateResults.contains {
            $0.gateID == "artifact-integrity" && $0.status == "blocked"
        })
        #expect(verification.gateResults.contains {
            $0.gateID == "native-drc" && $0.status == "blocked"
        })
        let correctnessGates = Dictionary(
            uniqueKeysWithValues: verification.correctnessGateResults.map { ($0.gateID, $0.status) }
        )
        #expect(correctnessGates["problem-validation"] == "not-evaluated")
        #expect(correctnessGates["action-domain-binding"] == "blocked")
        #expect(correctnessGates["planner-replay"] == "not-evaluated")
        #expect(correctnessGates["post-execution-signoff"] == "pending")
        #expect(correctnessGates["feedback-closure"] == "passed")
        #expect(verification.accepted == false)

        let actions = try await store.loadRunActions(runID: "run-1")
        let action = try #require(actions.last)
        #expect(action.actionKind == "planning.verify-candidate-plan")
        #expect(action.status == .blocked)
        #expect(action.inputs.contains(verification.candidatePlanRef))
        #expect(action.outputs.map(\.artifactID) == [XcircuitePlanningArtifactStore.planVerificationArtifactID])
        #expect(result.rejectedPlansArtifact?.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID)
        #expect(action.diagnostics.contains { $0.code == "unbound-operation-input-refs" })
        #expect(action.diagnostics.contains { $0.code == "unproven-operation-preconditions" })

        let ledger = try await store.loadRunLedger(runID: "run-1")
        #expect(ledger.runManifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        })
    }

    @Test func verifyCandidatePlanCLIRejectsTamperedCandidatePlanBeforeUse() async throws {
        let root = try makeTemporaryRoot("candidate-plan-verify-cli-tampered-plan")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        let generation = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        ).generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )
        try Data(#"{"tampered":true}"#.utf8).write(
            to: root.appending(path: generation.candidatePlanArtifact.path),
            options: [.atomic]
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
            ])
            Issue.record("Expected tampered candidate plan artifact to fail integrity verification.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, let reason) = error else {
                Issue.record("Unexpected ledger persistence error: \(error)")
                return
            }
            #expect(path == generation.candidatePlanArtifact.path)
            #expect(reason.contains("byteCountMismatch") || reason.contains("digestMismatch"))
        }
    }

    @Test func concurrentIdenticalVerificationReusesOneExactActionRecord() async throws {
        let root = try makeTemporaryRoot("candidate-plan-concurrent-idempotent-verification")
        defer { removeTemporaryRoot(root) }
        let runID = "run-concurrent-verification"
        let plan = XcircuiteCandidatePlan(
            planID: "concurrent-plan",
            problemID: "concurrent-problem",
            runID: runID,
            strategy: "verify-empty-completed-plan",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [],
            verificationGates: [],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
        let setupStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await setupStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: setupStore)
        let setupArtifactStore = XcircuitePlanningArtifactStore(workspaceStore: setupStore)
        _ = try await setupArtifactStore.persistPlanningProblem(
            makeRetainedPlanningProblem(for: plan),
            runID: runID,
            projectRoot: root
        )
        _ = try await setupArtifactStore.persistCandidatePlan(
            plan,
            runID: runID,
            projectRoot: root
        )
        _ = try await setupArtifactStore.persistActionDomainSnapshot(
            runID: runID,
            projectRoot: root,
            generatedAt: "2026-07-19T00:00:00Z"
        )

        try await withThrowingTaskGroup(of: XcircuiteCandidatePlanVerificationResult.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let store = try XcircuiteWorkspaceStore(projectRoot: root)
                    return try await XcircuiteCandidatePlanVerifier(
                        workspaceStore: store,
                        artifactStore: XcircuitePlanningArtifactStore(workspaceStore: store)
                    ).verifyCandidatePlan(
                        request: XcircuiteCandidatePlanVerificationRequest(runID: runID),
                        projectRoot: root
                    )
                }
            }
            for try await result in group {
                #expect(result.status == "accepted")
            }
        }

        let verificationActions = try await setupStore.loadRunActions(runID: runID).filter {
            $0.actionKind == "planning.verify-candidate-plan"
        }
        #expect(verificationActions.count == 1)
        let action = try #require(verificationActions.first)
        #expect(action.inputs.count == 1)
        #expect(action.outputs.count == 1)
    }

    @Test func runSelectedSuggestedActionDispatchesReadyVerifyCandidatePlan() async throws {
        let root = try makeTemporaryRoot("selected-action-verify-cli")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        _ = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: store,
            artifactStore: artifactStore
        ).generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-verify",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedAction: .init(
                    nextActionID: "verify-candidate-plan",
                    nextActionKind: "verifyPlanningCorrectness",
                    action: FlowRunSuggestedAction(
                        id: "verify-candidate-plan",
                        readiness: .ready,
                        operation: .verifyCandidatePlan(scope: .preExecution),
                        runID: "run-1",
                        reason: "Run preflight candidate-plan verification."
                    )
                ))
            ),
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-selected-suggested-action",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanVerificationResult.self, from: data)

        #expect(result.planVerificationArtifact.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID)
        let actions = try await XcircuiteWorkspaceStore(projectRoot: root).loadRunActions(runID: "run-1")
        #expect(actions.contains { $0.actionKind == "planning.verify-candidate-plan" })
    }

    @Test func runSelectedSuggestedActionDispatchesFeedbackAwareCandidatePlanGeneration() async throws {
        let root = try makeTemporaryRoot("selected-action-feedback-plan-cli")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        _ = try await XcircuitePlanningArtifactStore(workspaceStore: store).appendRejectedPlan(
            XcircuiteRejectedPlanRecord(
                rejectionID: "rejection-1",
                runID: "run-1",
                problemID: "run-1-drc-repair-problem",
                planID: "run-1-rejected-plan",
                verificationMode: "post-execution",
                status: "rejected",
                sourceParameterCandidateIDs: [],
                failedStepIDs: ["step-1"],
                failedGateIDs: ["native-drc"],
                candidatePlanRef: try fixtureArtifactReference(
                    artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                    path: ".xcircuite/runs/run-1/planning/candidate-plan.json",
                    kind: .other,
                    format: .json
                ),
                planVerificationRef: try fixtureArtifactReference(
                    artifactID: XcircuitePlanningArtifactStore.planVerificationArtifactID,
                    path: ".xcircuite/runs/run-1/planning/plan-verification.json",
                    kind: .other,
                    format: .json
                ),
                artifactRefs: [],
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "NATIVE_DRC_FAILED",
                        message: "Native DRC failed.",
                        gateID: "native-drc"
                    ),
                ],
                nextActions: ["repair-verification-gate:native-drc"]
            ),
            runID: "run-1",
            projectRoot: root
        )
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-generate-with-feedback",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedAction: .init(
                    nextActionID: "generate-candidate-plan.with-rejected-feedback",
                    nextActionKind: "regenerateCandidatePlanWithFeedback",
                    action: FlowRunSuggestedAction(
                        id: "generate-candidate-plan.with-rejected-feedback",
                        readiness: .ready,
                        operation: .generateCandidatePlan(
                            rejectedPlansArtifactID: try ArtifactID(
                                rawValue: XcircuitePlanningArtifactStore.rejectedPlansArtifactID
                            )
                        ),
                        runID: "run-1",
                        reason: "Regenerate planning/candidate-plan.json using feedback."
                    )
                ))
            ),
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-selected-suggested-action",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanGenerationResult.self, from: data)

        #expect(result.candidatePlanArtifact.path.hasPrefix(
            ".xcircuite/runs/run-1/planning/generated-candidate-plans/"
        ))
        #expect(result.candidatePlanArtifact.path.hasSuffix(
            "/\(result.candidatePlanArtifact.digest.hexadecimalValue).json"
        ))
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.rejectedPlansPath == ".xcircuite/runs/run-1/planning/rejected-plans.jsonl")
        #expect(trace.rejectedPlanFeedbackRecordCount == 1)
        #expect(trace.globalRejectedPlanFeedbackCount == 1)
    }

    @Test func runSelectedSuggestedActionRejectsInputDependentSelection() async throws {
        let root = try makeTemporaryRoot("selected-action-requires-input")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-requires-input",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedAction: .init(
                    nextActionID: "validate-planning-problem.after-goal-edit",
                    nextActionKind: "repairPlanningCorrectness",
                    action: FlowRunSuggestedAction(
                        id: "validate-planning-problem.after-goal-edit",
                        readiness: .requiresInput,
                        operation: .validatePlanningProblem,
                        runID: "run-1",
                        reason: "Edit planning/problem.json goal atoms first."
                    )
                ))
            ),
        )

        await #expect(throws: XcircuiteFlowCLIError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-action",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
        }
    }

    @Test func runSelectedSuggestedActionRejectsMismatchedSemanticRun() async throws {
        let root = try makeTemporaryRoot("selected-action-mismatched-run")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-mismatched-run",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedAction: .init(
                    nextActionID: "verify-candidate-plan",
                    nextActionKind: "verifyPlanningCorrectness",
                    action: FlowRunSuggestedAction(
                        id: "verify-candidate-plan",
                        readiness: .ready,
                        operation: .verifyCandidatePlan(scope: .preExecution),
                        runID: "other-run",
                        reason: "Verify the selected candidate plan."
                    )
                ))
            )
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-action",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
            Issue.record("Expected an action bound to another run to be rejected.")
        } catch let error as XcircuiteFlowCLIError {
            guard case .selectedSuggestedActionNotRunnable(let reason) = error else {
                Issue.record("Expected selected action rejection, got \(error).")
                return
            }
            #expect(reason.contains("run ID mismatch"))
        } catch {
            Issue.record("Expected CLI selected action error, got \(error).")
        }
    }
}
