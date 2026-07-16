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
        #expect(result.planVerificationArtifact.path == ".xcircuite/runs/run-1/planning/plan-verification.json")
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
        #expect(verification.candidatePlanRef.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
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
        #expect(action.inputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.candidatePlanArtifactID))
        #expect(action.outputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.planVerificationArtifactID))
        #expect(action.outputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.rejectedPlansArtifactID))
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
        } catch let error as XcircuiteCandidatePlanVerificationError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected candidate plan verification error: \(error)")
                return
            }
            #expect(path == generation.candidatePlanArtifact.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func runSelectedSuggestedCommandDispatchesReadyVerifyCandidatePlan() async throws {
        let root = try makeTemporaryRoot("selected-command-verify-cli")
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
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "verify-candidate-plan",
                    nextActionKind: "verifyPlanningCorrectness",
                    commandID: "xcircuite-flow.verify-candidate-plan",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: [
                        "verify-candidate-plan", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--pretty",
                    ],
                    reason: "Run preflight candidate-plan verification."
                ))
            ),
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-selected-suggested-command",
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

    @Test func runSelectedSuggestedCommandDispatchesFeedbackAwareCandidatePlanGeneration() async throws {
        let root = try makeTemporaryRoot("selected-command-feedback-plan-cli")
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
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "regenerate-candidate-plan-with-feedback",
                    nextActionKind: "regenerateCandidatePlanWithFeedback",
                    commandID: "xcircuite-flow.generate-candidate-plan.with-rejected-feedback",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: [
                        "generate-candidate-plan", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--rejected-plans-artifact-id",
                        XcircuitePlanningArtifactStore.rejectedPlansArtifactID, "--pretty",
                    ],
                    reason: "Regenerate planning/candidate-plan.json using feedback."
                ))
            ),
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-selected-suggested-command",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanGenerationResult.self, from: data)

        #expect(result.candidatePlanArtifact.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.rejectedPlansPath == ".xcircuite/runs/run-1/planning/rejected-plans.jsonl")
        #expect(trace.rejectedPlanFeedbackRecordCount == 1)
        #expect(trace.globalRejectedPlanFeedbackCount == 1)
    }

    @Test func runSelectedSuggestedCommandRejectsInputDependentSelection() async throws {
        let root = try makeTemporaryRoot("selected-command-requires-input")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-requires-input",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "repair-planning-problem-goals",
                    nextActionKind: "repairPlanningCorrectness",
                    commandID: "xcircuite-flow.validate-planning-problem.after-goal-edit",
                    readiness: "requiresInput",
                    executable: "xcircuite-flow",
                    arguments: [
                        "validate-planning-problem", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--pretty",
                    ],
                    reason: "Edit planning/problem.json goal atoms first."
                ))
            ),
        )

        await #expect(throws: XcircuiteFlowCLIError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-command",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
        }
    }

    @Test func runSelectedSuggestedCommandRejectsRepeatedRunIDOverride() async throws {
        let root = try makeTemporaryRoot("selected-command-run-id-override")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-verify-overridden-run",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "verify-candidate-plan",
                    nextActionKind: "verifyPlanningCorrectness",
                    commandID: "xcircuite-flow.verify-candidate-plan.override",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: [
                        "verify-candidate-plan", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--run-id", "other-run", "--pretty",
                    ],
                    reason: "Reject repeated run ID overrides before dispatch."
                ))
            ),
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-command",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
            Issue.record("Expected selected command with repeated run ID override to be rejected.")
        } catch let error as XcircuiteFlowCLIError {
            guard case .selectedSuggestedCommandNotRunnable(let reason) = error else {
                Issue.record("Expected selected command rejection, got \(error).")
                return
            }
            #expect(reason.contains("verify-candidate-plan"))
        } catch {
            Issue.record("Expected CLI selected command error, got \(error).")
        }
    }

    @Test func runSelectedSuggestedCommandRejectsAbsoluteArtifactPath() async throws {
        let root = try makeTemporaryRoot("selected-command-absolute-artifact-path")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-audit-absolute-path",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "audit-problem-translation",
                    nextActionKind: "auditProblemTranslation",
                    commandID: "xcircuite-flow.audit-problem-translation.absolute-path",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: [
                        "audit-problem-translation", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--problem-path", "/tmp/outside-planning-problem.json", "--pretty",
                    ],
                    reason: "Reject selected commands that point outside retained artifacts."
                ))
            ),
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-command",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
            Issue.record("Expected selected command with absolute artifact path to be rejected.")
        } catch let error as XcircuiteFlowCLIError {
            guard case .selectedSuggestedCommandNotRunnable(let reason) = error else {
                Issue.record("Expected selected command rejection, got \(error).")
                return
            }
            #expect(reason.contains("audit-problem-translation"))
        } catch {
            Issue.record("Expected CLI selected command error, got \(error).")
        }
    }

    @Test func runSelectedSuggestedCommandDispatchesSolverFamilyComparison() async throws {
        let root = try makeTemporaryRoot("selected-command-solver-family-comparison")
        defer { removeTemporaryRoot(root) }
        try await prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        try await XcircuiteWorkspaceStore(projectRoot: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-solver-family-comparison",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowSuggestedCommandSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedCommand: .init(
                    nextActionID: "compare-symbolic-planner-solver-family",
                    nextActionKind: "compareSymbolicPlannerSolverFamily",
                    commandID: "xcircuite-flow.compare-symbolic-planner-solver-family",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: [
                        "compare-symbolic-planner-solver-family", "--project-root", root.path(percentEncoded: false),
                        "--run-id", "run-1", "--comparison-id", "selected-comparison", "--pretty",
                    ],
                    reason: "Dispatch an allowlisted solver-family comparison command."
                ))
            ),
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "run-selected-suggested-command",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                ]
            )
            Issue.record("Expected solver family comparison to require qualification evidence.")
        } catch let error as XcircuiteSymbolicPlannerSolverError {
            #expect(error == .emptySolverFamilyComparison)
        } catch let error as XcircuiteFlowCLIError {
            if case .selectedSuggestedCommandNotRunnable(let reason) = error {
                Issue.record("Selected command resolver rejected a dispatchable comparison command: \(reason)")
            } else {
                Issue.record("Expected solver family comparison error, got \(error).")
            }
        } catch {
            Issue.record("Expected solver family comparison error, got \(error).")
        }
    }

}
