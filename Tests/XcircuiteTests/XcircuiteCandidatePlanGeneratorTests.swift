import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite candidate plan generator")
struct XcircuiteCandidatePlanGeneratorTests {
    @Test func generateCandidatePlanCLIReadsPlanningProblemFromRunManifest() async throws {
        let root = try makeTemporaryRoot("candidate-plan-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("rect-shape-created"),
                .string("artifact:layout-document"),
            ]),
        ]
        problem.costModel = XcircuitePlanningCostModel(
            strategy: "minimize-risk-then-churn",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "layout-churn",
                    weight: 3,
                    direction: "minimize",
                    description: "Prefer smaller physical edits."
                ),
            ]
        )
        let problemReference = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanGenerationResult.self, from: data)

        #expect(result.status == "generated")
        #expect(result.problemID == "run-1-drc-repair-problem")
        #expect(result.planID == "run-1-drc-repair-problem-candidate-plan-1")
        #expect(result.problemPath == problemReference.path)
        #expect(result.executionReadiness == "ready")
        #expect(result.candidatePlanArtifact.id.rawValue == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
        #expect(result.candidatePlanArtifact.locator.location.value == ".xcircuite/runs/run-1/planning/candidate-plan.json")
        #expect(!result.candidatePlanArtifact.digest.hexadecimalValue.isEmpty)
        #expect(result.candidatePlanArtifact.byteCount > 0)
        let translationAuditArtifact = try #require(result.problemTranslationAuditArtifact)
        #expect(translationAuditArtifact.id.rawValue == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        #expect(translationAuditArtifact.locator.location.value == ".xcircuite/runs/run-1/planning/problem-translation-audit.json")
        let actionDomainArtifact = try #require(result.actionDomainSnapshotArtifact)
        #expect(actionDomainArtifact.id.rawValue == XcircuitePlanningArtifactStore.actionDomainArtifactID)
        #expect(actionDomainArtifact.locator.location.value == ".xcircuite/runs/run-1/planning/action-domain-snapshot.json")
        #expect(!actionDomainArtifact.digest.hexadecimalValue.isEmpty)
        #expect(actionDomainArtifact.byteCount > 0)
        let traceArtifact = try #require(result.symbolicPlannerTraceArtifact)
        #expect(traceArtifact.id.rawValue == XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID)
        #expect(traceArtifact.locator.location.value == ".xcircuite/runs/run-1/planning/symbolic-planner-trace.json")
        #expect(!traceArtifact.digest.hexadecimalValue.isEmpty)
        #expect(traceArtifact.byteCount > 0)

        let plan = try store.readJSON(
            XcircuiteCandidatePlan.self,
            from: root.appending(path: result.candidatePlanArtifact.locator.location.value)
        )
        #expect(plan.sourceProblemRef.path == problemReference.path)
        #expect(plan.assumptions.map(\.assumptionID) == ["drc-summary-current"])
        #expect(plan.riskClassifications.map(\.riskID) == ["drc-layout-edit-risk"])
        #expect(plan.steps.map(\.operationID) == ["layout.add-rect"])
        #expect(plan.steps.first?.readiness == "ready")
        #expect(plan.steps.first?.missingInputRefs == [])
        #expect(plan.blockers == [])
        let inlineTrace = try #require(result.symbolicPlannerTrace)
        let trace = try store.readJSON(
            XcircuiteSymbolicPlannerTrace.self,
            from: root.appending(path: traceArtifact.path)
        )
        #expect(trace == inlineTrace)
        #expect(trace.problemID == problem.problemID)
        #expect(trace.generatedPlanID == plan.planID)
        #expect(trace.problemPath == problemReference.path)
        #expect(trace.actionDomainSnapshotPath == actionDomainArtifact.path)
        #expect(trace.actionDomainSnapshotArtifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID)
        #expect(trace.selectedActionIDs == ["layout-add-rect-1"])
        #expect(trace.unresolvedObjectiveIDs == [])
        #expect(trace.initialSymbolicState.contains("ref:drc-summary"))
        #expect(trace.finalSymbolicState.contains("rect-shape-created"))
        #expect(trace.goalCoverageStatus == "covered")
        #expect(trace.missingGoalAtoms == [])
        let coverage = try #require(trace.goalCoverage.first)
        #expect(coverage.objectiveID == "drc-m1-width-1")
        #expect(coverage.status == "covered")
        #expect(coverage.satisfiedGoalAtoms == [
            "rect-shape-created",
            "artifact:layout-document",
        ])
        #expect(coverage.missingGoalAtoms == [])
        let objectiveTrace = try #require(trace.objectiveTraces.first)
        #expect(objectiveTrace.objectiveID == "drc-m1-width-1")
        #expect(objectiveTrace.selectedActionID == "layout-add-rect-1")
        #expect(objectiveTrace.unresolvedReason == nil)
        #expect(objectiveTrace.candidateActions.map(\.actionID) == ["layout-add-rect-1"])
        #expect(objectiveTrace.candidateActions.map(\.rank) == [1])
        #expect(objectiveTrace.candidateActions.map(\.score) == [129])
        let selectedAction = try #require(objectiveTrace.candidateActions.first)
        #expect(selectedAction.selected == true)
        #expect(selectedAction.actionDomainSupported == true)
        #expect(selectedAction.operationSupported == true)
        #expect(selectedAction.operationMaturity == "implemented")
        #expect(selectedAction.operationReversible == true)
        #expect(selectedAction.operationPreconditions.isEmpty == false)
        #expect(selectedAction.operationEffects.isEmpty == false)
        #expect(selectedAction.operationProducedArtifacts.isEmpty == false)
        #expect(selectedAction.operationVerificationGates.contains("native-drc"))
        #expect(selectedAction.objectiveGoalAtoms == [
            "rect-shape-created",
            "artifact:layout-document",
        ])
        #expect(selectedAction.candidateEffectAtoms.contains("rect-shape-created"))
        #expect(selectedAction.candidateEffectAtoms.contains("artifact:layout-document"))
        #expect(selectedAction.matchedObjectiveGoalAtoms == [
            "rect-shape-created",
            "artifact:layout-document",
        ])
        #expect(selectedAction.missingObjectiveGoalAtoms == [])
        #expect(selectedAction.symbolicStateBefore.contains("ref:drc-summary"))
        #expect(selectedAction.symbolicStateBefore.contains("artifact:drc-summary"))
        #expect(selectedAction.symbolicStateBefore.contains("ref:layout-ref"))
        #expect(selectedAction.symbolicStateAfter.contains("rect-shape-created"))
        #expect(selectedAction.symbolicStateAfter.contains("artifact:layout-document"))
        #expect(selectedAction.satisfiedPreconditionAtoms == [])
        #expect(selectedAction.unsatisfiedPreconditionAtoms == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(selectedAction.scoreComponents.contains {
            $0.termID == "maturity.implemented" && $0.contribution == 100
        })
        #expect(selectedAction.scoreComponents.contains {
            $0.termID == "layout-churn" && $0.contribution == -3
        })
        #expect(selectedAction.scoreComponents.contains {
            $0.termID == "objective-goal-effect-match" && $0.contribution == 50
        })
        #expect(selectedAction.scoreComponents.contains {
            $0.termID == "symbolic-precondition-unproven" && $0.contribution == -18
        })

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID
                && $0.path == result.candidatePlanArtifact.path
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID
                && $0.path == translationAuditArtifact.path
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
                && $0.path == actionDomainArtifact.path
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID
                && $0.path == traceArtifact.path
        })
    }

    @Test func generateCandidatePlanBlocksWhenTranslationAuditBlocks() async throws {
        let root = try makeTemporaryRoot("candidate-plan-audit-block")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].sourceRefIDs = []
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "generate-candidate-plan",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                    "--pretty",
                ]
            )
        }
    }

    @Test func generateCandidatePlanRefreshesStalePassedAuditAndBlocksMutatedProblem() async throws {
        let root = try makeTemporaryRoot("candidate-plan-stale-audit")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        let problemRef = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )
        let staleAudit = try XcircuiteProblemTranslationAuditor().auditProblemTranslation(
            request: XcircuiteProblemTranslationAuditRequest(
                runID: "run-1",
                problemPath: problemRef.path
            ),
            projectRoot: root
        )
        #expect(staleAudit.audit.blocking == false)
        #expect(staleAudit.audit.status == "passed")

        problem.objectives[0].sourceRefIDs = []
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "generate-candidate-plan",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                    "--pretty",
                ]
            )
        }

        let refreshedAudit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: staleAudit.auditArtifact.path)
        )
        #expect(refreshedAudit.blocking == true)
        #expect(refreshedAudit.status == "failed")
        #expect(refreshedAudit.diagnostics.contains {
            $0.code == "orphan-objective" && $0.objectiveID == "drc-m1-width-1"
        })
        #expect(refreshedAudit.diagnostics.contains {
            $0.code == "orphan-candidate-action" && $0.actionID == "layout-add-rect-1"
        })
    }

    @Test func generateCandidatePlanRefreshesTamperedActionDomainSnapshotBeforeUse() throws {
        let root = try makeTemporaryRoot("candidate-plan-tampered-action-domain")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        let verifier = XcircuiteFileReferenceVerifier()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("rect-shape-created"),
                .string("artifact:layout-document"),
            ]),
        ]
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )
        let staleReference = try artifactStore.persistActionDomainSnapshot(
            runID: "run-1",
            projectRoot: root,
            generatedAt: "before-tamper"
        )
        let tamperedSnapshot = XcircuitePlanningActionDomainSnapshot(
            runID: "run-1",
            generatedAt: "tampered",
            domains: []
        )
        try store.writeJSON(
            tamperedSnapshot,
            to: root.appending(path: staleReference.path),
            forProjectAt: root
        )
        let staleIntegrity = verifier.verify(staleReference, projectRoot: root)
        #expect(staleIntegrity.status != .verified)

        let result = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )

        #expect(result.status == "generated")
        #expect(result.executionReadiness == "ready")
        let actionDomainArtifact = try #require(result.actionDomainSnapshotArtifact)
        let refreshedIntegrity = LocalArtifactVerifier().verify(actionDomainArtifact, relativeTo: root)
        #expect(refreshedIntegrity.isVerified)
        #expect(actionDomainArtifact.digest.hexadecimalValue != staleReference.sha256)
        let refreshedSnapshot = try store.readJSON(
            XcircuitePlanningActionDomainSnapshot.self,
            from: root.appending(path: actionDomainArtifact.locator.location.value)
        )
        #expect(refreshedSnapshot.runID == "run-1")
        #expect(refreshedSnapshot.domains.isEmpty == false)
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.selectedActionIDs == ["layout-add-rect-1"])

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        let manifestActionDomain = try #require(manifest.artifacts.first {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        })
        #expect(manifestActionDomain.sha256 == actionDomainArtifact.digest.hexadecimalValue)
        #expect(actionDomainArtifact.byteCount == UInt64(manifestActionDomain.byteCount ?? 0))
    }

    @Test func generateCandidatePlanRejectsTamperedPlanningProblemManifestArtifactBeforeUse() throws {
        let root = try makeTemporaryRoot("candidate-plan-tampered-problem")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        let problemReference = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )
        problem.objectives[0].sourceRefIDs = []
        try store.writeJSON(
            problem,
            to: root.appending(path: problemReference.path),
            forProjectAt: root
        )

        do {
            _ = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
                request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
                projectRoot: root
            )
            Issue.record("Expected tampered planning problem artifact to fail integrity verification.")
        } catch let error as XcircuiteCandidatePlanGenerationError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected candidate plan generation error: \(error)")
                return
            }
            #expect(path == problemReference.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func lvsPolicyRepairCandidateIsReadyButApprovalTracked() throws {
        let problem = makeLVSPlanningProblem()
        let plan = try XcircuiteCandidatePlanGenerator().makeCandidatePlan(
            problem: problem,
            problemPath: ".xcircuite/runs/run-2/planning/problem.json"
        )

        #expect(plan.executionReadiness == "ready")
        #expect(plan.assumptions.map(\.assumptionID) == ["lvs-summary-current"])
        #expect(plan.riskClassifications.map(\.riskID) == ["lvs-policy-mutation-risk"])
        #expect(plan.riskClassifications.first?.requiredApprovals == ["policy-repair-approval"])
        #expect(plan.steps.map(\.operationID) == ["lvs.policy-repair"])
        #expect(plan.steps.first?.maturity == "implemented")
        #expect(plan.steps.first?.readiness == "ready")
        #expect(plan.steps.first?.blockers.isEmpty == true)
        #expect(plan.blockers.isEmpty)
    }

    @Test func missingInputReferenceBlocksCandidatePlan() throws {
        var problem = makeDRCPlanningProblem()
        problem.initialStateRefs = []

        let plan = try XcircuiteCandidatePlanGenerator().makeCandidatePlan(
            problem: problem,
            problemPath: ".xcircuite/runs/run-1/planning/problem.json"
        )

        #expect(plan.executionReadiness == "blocked")
        #expect(plan.steps.first?.readiness == "blocked")
        #expect(plan.steps.first?.missingInputRefs == ["layout-ref"])
        #expect(plan.steps.first?.blockers.contains("missing-input-refs:layout-ref") == true)
    }

    @Test func duplicateInputReferencesDoNotCrashCandidatePlanGeneration() throws {
        var problem = makeDRCPlanningProblem()
        problem.initialStateRefs.insert(
            XcircuitePlanningReference(refID: "layout-ref", kind: "layout"),
            at: 0
        )

        let plan = try XcircuiteCandidatePlanGenerator().makeCandidatePlan(
            problem: problem,
            problemPath: ".xcircuite/runs/run-1/planning/problem.json"
        )

        #expect(plan.executionReadiness == "ready")
        #expect(plan.steps.first?.missingInputRefs == [])
        #expect(plan.blockers == [])
    }

    @Test func generatedTraceCarriesSymbolicStateAcrossSelectedSteps() throws {
        let root = try makeTemporaryRoot("candidate-plan-state-progression")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-state", inProjectAt: root)
        let problem = makeStateProgressionPlanningProblem()
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-state",
            projectRoot: root
        )

        let result = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-state"),
            projectRoot: root
        )

        #expect(result.executionReadiness == "ready")
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.selectedActionIDs == ["create-cell-step", "add-rect-step"])
        #expect(trace.goalCoverageStatus == "covered")
        #expect(trace.finalSymbolicState.contains("cell-exists"))
        #expect(trace.finalSymbolicState.contains("rect-shape-created"))
        #expect(trace.goalCoverage.map(\.status) == ["covered", "covered"])
        let createObjective = try #require(trace.objectiveTraces.first {
            $0.objectiveID == "create-cell-objective"
        })
        let createAction = try #require(createObjective.candidateActions.first)
        #expect(createAction.selected == true)
        #expect(createAction.satisfiedPreconditionAtoms == ["unique-cell-id", "valid-cell-name"])
        #expect(createAction.unsatisfiedPreconditionAtoms == [])
        #expect(createAction.matchedObjectiveGoalAtoms == ["cell-created", "cell-exists"])
        #expect(createAction.symbolicStateAfter.contains("cell-created"))
        #expect(createAction.symbolicStateAfter.contains("cell-exists"))

        let rectObjective = try #require(trace.objectiveTraces.first {
            $0.objectiveID == "add-rect-objective"
        })
        let rectAction = try #require(rectObjective.candidateActions.first)
        #expect(rectAction.selected == true)
        #expect(rectAction.symbolicStateBefore.contains("cell-exists"))
        #expect(rectAction.satisfiedPreconditionAtoms == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(rectAction.unsatisfiedPreconditionAtoms == [])
        #expect(rectAction.matchedObjectiveGoalAtoms == ["rect-shape-created"])
        #expect(rectAction.symbolicStateAfter.contains("rect-shape-created"))
        #expect(rectAction.scoreComponents.contains {
            $0.termID == "symbolic-precondition-satisfied" && $0.contribution == 30
        })
    }

    @Test func stateAwareStrategyOrdersObjectivesBySymbolicReadiness() throws {
        let root = try makeTemporaryRoot("candidate-plan-state-aware-ordering")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-state", inProjectAt: root)
        var problem = makeStateProgressionPlanningProblem()
        problem.objectives.reverse()
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-state",
            projectRoot: root
        )

        let result = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(
                runID: "run-state",
                strategy: "state-aware-objective-ordering"
            ),
            projectRoot: root
        )

        #expect(result.executionReadiness == "ready")
        let plan = try store.readJSON(
            XcircuiteCandidatePlan.self,
            from: root.appending(path: result.candidatePlanArtifact.path)
        )
        #expect(plan.strategy == "state-aware-objective-ordering")
        #expect(plan.steps.map(\.actionID) == ["create-cell-step", "add-rect-step"])

        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.strategy == "state-aware-objective-ordering")
        #expect(trace.objectiveTraces.map(\.objectiveID) == [
            "create-cell-objective",
            "add-rect-objective",
        ])
        #expect(trace.goalCoverageStatus == "covered")
        #expect(trace.selectedActionIDs == ["create-cell-step", "add-rect-step"])
        let rectTrace = try #require(trace.objectiveTraces.last?.candidateActions.first)
        #expect(rectTrace.actionID == "add-rect-step")
        #expect(rectTrace.symbolicStateBefore.contains("cell-exists"))
        #expect(rectTrace.satisfiedPreconditionAtoms == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(rectTrace.unsatisfiedPreconditionAtoms == [])
    }

    @Test func globalRejectedPlanFeedbackPenalizesMatchingSymbolicActionGate() async throws {
        let root = try makeTemporaryRoot("candidate-plan-global-feedback")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-global-feedback", inProjectAt: root)
        let problem = makeGlobalFeedbackPlanningProblem()
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-global-feedback",
            projectRoot: root
        )
        try XcircuitePlanningArtifactStore().appendRejectedPlan(
            rejectedPlanRecord(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                planID: "run-global-feedback-post-waiver-drc",
                failedGateIDs: ["post-waiver-edit-drc"]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-global-feedback",
                "--pretty",
            ]
        )
        let result = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        #expect(result.executionReadiness == "ready")
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.rejectedPlansPath == ".xcircuite/runs/run-global-feedback/planning/rejected-plans.jsonl")
        #expect(trace.rejectedPlanFeedbackRecordCount == 1)
        #expect(trace.globalRejectedPlanFeedbackCount == 1)
        #expect(trace.selectedActionIDs == ["b-lvs-preserving-layout-repair"])
        let objectiveTrace = try #require(trace.objectiveTraces.first {
            $0.objectiveID == "layout-repair-objective"
        })
        #expect(objectiveTrace.selectedActionID == "b-lvs-preserving-layout-repair")
        #expect(objectiveTrace.candidateActions.map(\.actionID) == [
            "b-lvs-preserving-layout-repair",
            "a-drc-sensitive-layout-repair",
        ])
        let drcAction = try #require(objectiveTrace.candidateActions.first {
            $0.actionID == "a-drc-sensitive-layout-repair"
        })
        let lvsAction = try #require(objectiveTrace.candidateActions.first {
            $0.actionID == "b-lvs-preserving-layout-repair"
        })
        #expect(drcAction.selected == false)
        #expect(drcAction.rank == 2)
        #expect(drcAction.rankBeforeRejectedFeedback == 1)
        #expect(drcAction.rejectedFeedbackRankDelta == 1)
        #expect(drcAction.rejectedFeedbackScoreDelta < 0)
        #expect(drcAction.score == drcAction.scoreBeforeRejectedFeedback + drcAction.rejectedFeedbackScoreDelta)
        #expect(drcAction.scoreComponents.contains {
            $0.termID == "feedback.global.failed-gate" && $0.contribution < 0
        })
        #expect(drcAction.scoreComponents.contains {
            $0.reason.contains("post-waiver-edit-drc")
        })
        #expect(lvsAction.selected == true)
        #expect(lvsAction.rank == 1)
        #expect(lvsAction.rankBeforeRejectedFeedback == 2)
        #expect(lvsAction.rejectedFeedbackRankDelta == -1)
        #expect(lvsAction.rejectedFeedbackScoreDelta == 0)
        #expect(lvsAction.score == lvsAction.scoreBeforeRejectedFeedback)
        #expect(lvsAction.scoreComponents.contains {
            $0.termID == "feedback.global.failed-gate"
        } == false)
    }

    @Test func cp7CalibrationPenalizesMatchingSymbolicActionGate() async throws {
        let root = try makeTemporaryRoot("candidate-plan-cp7-calibration")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-global-feedback", inProjectAt: root)
        let problem = makeGlobalFeedbackPlanningProblem()
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistMetricThresholdProfile(
            XcircuiteMetricThresholdProfile(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                profileID: "run-global-feedback-threshold-profile",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholds: [
                    XcircuiteMetricThresholdProfile.Threshold(
                        metricID: "layout-repair-objective",
                        objectiveID: "layout-repair-objective",
                        domain: "layout",
                        metricName: "native-drc",
                        direction: "within-tolerance",
                        targetValue: 0,
                        severity: "error",
                        sourceRefIDs: ["layout-ref"]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistCostCalibrationReport(
            XcircuiteCostCalibrationReport(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                calibrationID: "run-global-feedback-cost-calibration",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                inputArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                calibratedTerms: [
                    XcircuiteCostCalibrationReport.Term(
                        termID: "feedback.gate.native-drc",
                        gateID: "native-drc",
                        baseWeight: 1,
                        calibratedWeight: 3,
                        evidenceCount: 2,
                        rationale: "Repeated native DRC failures should demote matching symbolic actions."
                    ),
                ],
                observations: [
                    XcircuiteCostCalibrationReport.Observation(
                        candidateID: "a-drc-sensitive-layout-repair",
                        accepted: false,
                        selectedTotalScore: 100,
                        failedGateIDs: ["native-drc"],
                        sourceArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistParetoCandidates(
            XcircuiteParetoCandidateSet(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                costCalibrationArtifactID: XcircuitePlanningArtifactStore.costCalibrationArtifactID,
                sourceCandidateArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                candidates: [
                    XcircuiteParetoCandidateSet.Candidate(
                        runID: "run-global-feedback",
                        problemID: problem.problemID,
                        generatedAt: "2026-06-23T00:00:00Z",
                        candidateID: "iteration-1-a-drc-sensitive-layout-repair",
                        sourceCandidateID: "a-drc-sensitive-layout-repair",
                        frontierRank: 3,
                        dominatedByCandidateIDs: ["iteration-1-b-lvs-preserving-layout-repair"],
                        metrics: [],
                        gateStatuses: ["native-drc": "failed"],
                        rationale: "The DRC-sensitive symbolic action repeatedly failed native DRC."
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-global-feedback",
                "--strategy",
                "calibrated-first-ready-action-per-objective",
                "--pretty",
            ]
        )
        let result = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        #expect(result.executionReadiness == "ready")
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.selectedActionIDs == ["b-lvs-preserving-layout-repair"])
        let calibrationTrace = try #require(trace.calibrationTrace)
        #expect(calibrationTrace.strategy == "calibrated-first-ready-action-per-objective")
        #expect(calibrationTrace.thresholdCount == 1)
        #expect(calibrationTrace.calibratedTermCount == 1)
        #expect(calibrationTrace.paretoCandidateCount == 1)
        #expect(calibrationTrace.appliedActionCount == 1)
        #expect(calibrationTrace.matchedActionIDs == ["a-drc-sensitive-layout-repair"])
        #expect(calibrationTrace.matchedGateIDs == ["native-drc"])
        let objectiveTrace = try #require(trace.objectiveTraces.first {
            $0.objectiveID == "layout-repair-objective"
        })
        #expect(objectiveTrace.selectedActionID == "b-lvs-preserving-layout-repair")
        #expect(objectiveTrace.candidateActions.map(\.actionID) == [
            "b-lvs-preserving-layout-repair",
            "a-drc-sensitive-layout-repair",
        ])
        let drcAction = try #require(objectiveTrace.candidateActions.first {
            $0.actionID == "a-drc-sensitive-layout-repair"
        })
        #expect(drcAction.selected == false)
        #expect(drcAction.scoreComponents.contains {
            $0.termID == "cp7.calibrated-gate.native-drc" && $0.contribution < 0
        })
        #expect(drcAction.scoreComponents.contains {
            $0.termID == "cp7.pareto-failed-gates" && $0.contribution < 0
        })
        #expect(drcAction.scoreComponents.contains {
            $0.termID == "cp7.pareto-dominance" && $0.contribution < 0
        })
    }

    @Test func cp7PolicySelectsCalibratedSymbolicStrategyFromRunManifest() async throws {
        let root = try makeTemporaryRoot("candidate-plan-cp7-policy")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-global-feedback", inProjectAt: root)
        let problem = makeGlobalFeedbackPlanningProblem()
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistMetricThresholdProfile(
            XcircuiteMetricThresholdProfile(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                profileID: "run-global-feedback-threshold-profile",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholds: [
                    XcircuiteMetricThresholdProfile.Threshold(
                        metricID: "layout-repair-objective",
                        objectiveID: "layout-repair-objective",
                        domain: "layout",
                        metricName: "native-drc",
                        direction: "within-tolerance",
                        targetValue: 0,
                        severity: "error",
                        sourceRefIDs: ["layout-ref"]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistCostCalibrationReport(
            XcircuiteCostCalibrationReport(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                calibrationID: "run-global-feedback-cost-calibration",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                inputArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                calibratedTerms: [
                    XcircuiteCostCalibrationReport.Term(
                        termID: "feedback.gate.native-drc",
                        gateID: "native-drc",
                        baseWeight: 1,
                        calibratedWeight: 3,
                        evidenceCount: 2,
                        rationale: "Repeated native DRC failures should demote matching symbolic actions."
                    ),
                ],
                observations: [
                    XcircuiteCostCalibrationReport.Observation(
                        candidateID: "a-drc-sensitive-layout-repair",
                        accepted: false,
                        selectedTotalScore: 100,
                        failedGateIDs: ["native-drc"],
                        sourceArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistParetoCandidates(
            XcircuiteParetoCandidateSet(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                costCalibrationArtifactID: XcircuitePlanningArtifactStore.costCalibrationArtifactID,
                sourceCandidateArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                candidates: [
                    XcircuiteParetoCandidateSet.Candidate(
                        runID: "run-global-feedback",
                        problemID: problem.problemID,
                        generatedAt: "2026-06-23T00:00:00Z",
                        candidateID: "iteration-1-a-drc-sensitive-layout-repair",
                        sourceCandidateID: "a-drc-sensitive-layout-repair",
                        frontierRank: 3,
                        dominatedByCandidateIDs: ["iteration-1-b-lvs-preserving-layout-repair"],
                        metrics: [],
                        gateStatuses: ["native-drc": "failed"],
                        rationale: "The DRC-sensitive symbolic action repeatedly failed native DRC."
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-global-feedback",
                "--calibration-policy",
                "cp7-feedback",
                "--pretty",
            ]
        )
        let result = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        let trace = try #require(result.symbolicPlannerTrace)
        #expect(trace.strategy == "calibrated-first-ready-action-per-objective")
        let policyTrace = try #require(trace.policyTrace)
        #expect(policyTrace.calibrationPolicy == "cp7-feedback")
        #expect(policyTrace.baseStrategy == "first-ready-action-per-objective")
        #expect(policyTrace.selectedStrategy == "calibrated-first-ready-action-per-objective")
        #expect(policyTrace.usesCalibrationArtifacts)
        #expect(policyTrace.reasonCodes.contains("calibrated-symbolic-strategy-selected"))
        #expect(policyTrace.metricThresholdProfileArtifact?.artifactID == XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID)
        #expect(policyTrace.costCalibrationArtifact?.artifactID == XcircuitePlanningArtifactStore.costCalibrationArtifactID)
        #expect(policyTrace.paretoCandidatesArtifact?.artifactID == XcircuitePlanningArtifactStore.paretoCandidatesArtifactID)
        let calibrationTrace = try #require(trace.calibrationTrace)
        #expect(calibrationTrace.strategy == "calibrated-first-ready-action-per-objective")
        #expect(calibrationTrace.appliedActionCount == 1)
        #expect(trace.selectedActionIDs == ["b-lvs-preserving-layout-repair"])

        let persistedTrace = try store.readJSON(
            XcircuiteSymbolicPlannerTrace.self,
            from: root.appending(path: try #require(result.symbolicPlannerTraceArtifact).path)
        )
        #expect(persistedTrace.policyTrace == policyTrace)
        #expect(persistedTrace.calibrationTrace == calibrationTrace)
    }

    @Test func symbolicPlannerFamilyPromotesSelectedCP7CalibratedCandidate() async throws {
        let root = try makeTemporaryRoot("symbolic-planner-family-cp7")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-global-feedback", inProjectAt: root)
        let problem = makeGlobalFeedbackPlanningProblem()
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistMetricThresholdProfile(
            XcircuiteMetricThresholdProfile(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                profileID: "run-global-feedback-threshold-profile",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholds: [
                    XcircuiteMetricThresholdProfile.Threshold(
                        metricID: "layout-repair-objective",
                        objectiveID: "layout-repair-objective",
                        domain: "layout",
                        metricName: "native-drc",
                        direction: "within-tolerance",
                        targetValue: 0,
                        severity: "error",
                        sourceRefIDs: ["layout-ref"]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistCostCalibrationReport(
            XcircuiteCostCalibrationReport(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                calibrationID: "run-global-feedback-cost-calibration",
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                inputArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                calibratedTerms: [
                    XcircuiteCostCalibrationReport.Term(
                        termID: "feedback.gate.native-drc",
                        gateID: "native-drc",
                        baseWeight: 1,
                        calibratedWeight: 3,
                        evidenceCount: 2,
                        rationale: "Repeated native DRC failures should demote matching symbolic actions."
                    ),
                ],
                observations: [
                    XcircuiteCostCalibrationReport.Observation(
                        candidateID: "a-drc-sensitive-layout-repair",
                        accepted: false,
                        selectedTotalScore: 100,
                        failedGateIDs: ["native-drc"],
                        sourceArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID]
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )
        try artifactStore.persistParetoCandidates(
            XcircuiteParetoCandidateSet(
                runID: "run-global-feedback",
                problemID: problem.problemID,
                generatedAt: "2026-06-23T00:00:00Z",
                thresholdProfileArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
                costCalibrationArtifactID: XcircuitePlanningArtifactStore.costCalibrationArtifactID,
                sourceCandidateArtifactIDs: [XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID],
                candidates: [
                    XcircuiteParetoCandidateSet.Candidate(
                        runID: "run-global-feedback",
                        problemID: problem.problemID,
                        generatedAt: "2026-06-23T00:00:00Z",
                        candidateID: "iteration-1-a-drc-sensitive-layout-repair",
                        sourceCandidateID: "a-drc-sensitive-layout-repair",
                        frontierRank: 3,
                        dominatedByCandidateIDs: ["iteration-1-b-lvs-preserving-layout-repair"],
                        metrics: [],
                        gateStatuses: ["native-drc": "failed"],
                        rationale: "The DRC-sensitive symbolic action repeatedly failed native DRC."
                    ),
                ]
            ),
            runID: "run-global-feedback",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-symbolic-planner-family",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-global-feedback",
                "--family-run-id",
                "cp7-family",
                "--strategy",
                "first-ready-action-per-objective",
                "--strategy",
                "state-aware-objective-ordering",
                "--calibration-policy",
                "cp7-feedback",
                "--pretty",
            ]
        )
        let result = try JSONDecoder().decode(
            XcircuiteSymbolicPlannerFamilyRunResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "generated")
        #expect(result.familyRunArtifact.artifactID == "planning-symbolic-planner-family-run-cp7-family")
        #expect(result.familyRun.status == "generated")
        #expect(result.familyRun.familyRunID == "cp7-family")
        #expect(result.familyRun.requestedStrategies == [
            "first-ready-action-per-objective",
            "state-aware-objective-ordering",
        ])
        #expect(result.familyRun.candidates.count == 2)
        #expect(result.familyRun.selectedCandidateIndex == 0)
        #expect(result.familyRun.selectedStrategy == "calibrated-first-ready-action-per-objective")
        #expect(result.familyRun.selectedPlanID == "run-global-feedback-symbolic-problem-candidate-plan-1")
        #expect(result.familyRun.promotedCandidatePlanArtifact.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
        #expect(result.familyRun.promotedSymbolicPlannerTraceArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerTraceArtifactID)

        let selectedCandidate = try #require(result.familyRun.candidates.first { $0.selected })
        #expect(selectedCandidate.requestedStrategy == "first-ready-action-per-objective")
        #expect(selectedCandidate.effectiveStrategy == "calibrated-first-ready-action-per-objective")
        #expect(selectedCandidate.selectedActionIDs == ["b-lvs-preserving-layout-repair"])
        #expect(selectedCandidate.candidatePlanArtifact.path.contains("planning/symbolic-planner/family/cp7-family/candidates/1-first-ready-action-per-objective/candidate-plan.json"))
        #expect(selectedCandidate.symbolicPlannerTraceArtifact.path.contains("planning/symbolic-planner/family/cp7-family/candidates/1-first-ready-action-per-objective/symbolic-planner-trace.json"))
        #expect(selectedCandidate.policyTrace?.usesCalibrationArtifacts == true)
        #expect(selectedCandidate.calibrationTrace?.appliedActionCount == 1)
        #expect(selectedCandidate.scoreComponents.contains {
            $0.termID == "cp7.policy-artifacts-used" && $0.contribution > 0
        })

        let familyRun = try store.readJSON(
            XcircuiteSymbolicPlannerFamilyRun.self,
            from: root.appending(path: result.familyRunArtifact.path)
        )
        #expect(familyRun == result.familyRun)
        let promotedPlan = try store.readJSON(
            XcircuiteCandidatePlan.self,
            from: root.appending(path: result.familyRun.promotedCandidatePlanArtifact.path)
        )
        #expect(promotedPlan.strategy == result.familyRun.selectedStrategy)
        #expect(promotedPlan.steps.map(\.actionID) == ["b-lvs-preserving-layout-repair"])
        let promotedTrace = try store.readJSON(
            XcircuiteSymbolicPlannerTrace.self,
            from: root.appending(path: result.familyRun.promotedSymbolicPlannerTraceArtifact.path)
        )
        #expect(promotedTrace.strategy == result.familyRun.selectedStrategy)
        #expect(promotedTrace.policyTrace?.usesCalibrationArtifacts == true)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-global-feedback/manifest.json")
        )
        #expect(manifest.artifacts.contains { $0.path == result.familyRunArtifact.path })
        #expect(manifest.artifacts.contains { $0.path == selectedCandidate.candidatePlanArtifact.path })
        #expect(manifest.artifacts.contains { $0.path == selectedCandidate.symbolicPlannerTraceArtifact.path })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID
                && $0.path == result.familyRun.promotedCandidatePlanArtifact.path
        })
    }

    @Test func symbolicPlannerFamilyRejectsExistingFamilyRunOutputs() throws {
        let root = try makeTemporaryRoot("symbolic-planner-family-reuse")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        let generator = XcircuiteCandidatePlanGenerator()
        let verifier = XcircuiteFileReferenceVerifier()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("rect-shape-created"),
                .string("artifact:layout-document"),
            ]),
        ]
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )
        let request = XcircuiteSymbolicPlannerFamilyRunRequest(
            runID: "run-1",
            familyRunID: "family-immutability",
            strategies: ["first-ready-action-per-objective"]
        )
        let first = try generator.runSymbolicPlannerFamily(request: request, projectRoot: root)
        let selectedPlanArtifact = first.familyRun.selectedCandidatePlanArtifact
        let selectedPlanSHA256 = try #require(selectedPlanArtifact.sha256)
        #expect(verifier.verify(selectedPlanArtifact, projectRoot: root).status == .verified)

        do {
            _ = try generator.runSymbolicPlannerFamily(request: request, projectRoot: root)
            Issue.record("Expected family run reuse to be rejected.")
        } catch let error as XcircuiteCandidatePlanGenerationError {
            #expect(error == .familyRunAlreadyExists(
                runID: "run-1",
                familyRunID: "family-immutability",
                path: ".xcircuite/runs/run-1/planning/symbolic-planner/family/family-immutability/"
            ))
        } catch {
            Issue.record("Expected XcircuiteCandidatePlanGenerationError, got \(error).")
        }

        let selectedPlanIntegrity = verifier.verify(selectedPlanArtifact, projectRoot: root)
        #expect(selectedPlanIntegrity.status == .verified)
        #expect(selectedPlanIntegrity.actualSHA256 == selectedPlanSHA256)
        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.filter { $0.path == selectedPlanArtifact.path }.count == 1)
        #expect(manifest.artifacts.contains {
            $0.artifactID == selectedPlanArtifact.artifactID
                && $0.path == selectedPlanArtifact.path
                && $0.sha256 == selectedPlanArtifact.sha256
        })
    }

    @Test func symbolicPlannerFamilyCandidateArtifactIDsAreScopedByFamilyRun() throws {
        let root = try makeTemporaryRoot("symbolic-planner-family-artifact-id-scope")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        let generator = XcircuiteCandidatePlanGenerator()
        let verifier = XcircuiteFileReferenceVerifier()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("rect-shape-created"),
                .string("artifact:layout-document"),
            ]),
        ]
        _ = try artifactStore.persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        let first = try generator.runSymbolicPlannerFamily(
            request: XcircuiteSymbolicPlannerFamilyRunRequest(
                runID: "run-1",
                familyRunID: "family-a",
                strategies: ["first-ready-action-per-objective"]
            ),
            projectRoot: root
        )
        let second = try generator.runSymbolicPlannerFamily(
            request: XcircuiteSymbolicPlannerFamilyRunRequest(
                runID: "run-1",
                familyRunID: "family-b",
                strategies: ["first-ready-action-per-objective"]
            ),
            projectRoot: root
        )
        let firstPlanArtifact = first.familyRun.selectedCandidatePlanArtifact
        let secondPlanArtifact = second.familyRun.selectedCandidatePlanArtifact
        #expect(firstPlanArtifact.artifactID != secondPlanArtifact.artifactID)
        #expect(firstPlanArtifact.path.contains("family/family-a/candidates/1-first-ready-action-per-objective"))
        #expect(secondPlanArtifact.path.contains("family/family-b/candidates/1-first-ready-action-per-objective"))
        #expect(verifier.verify(firstPlanArtifact, projectRoot: root).status == .verified)
        #expect(verifier.verify(secondPlanArtifact, projectRoot: root).status == .verified)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == firstPlanArtifact.artifactID && $0.path == firstPlanArtifact.path
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == secondPlanArtifact.artifactID && $0.path == secondPlanArtifact.path
        })
    }

    @Test func unsupportedGoalAtomsBlockCandidatePlanBeforeGeneration() async throws {
        let root = try makeTemporaryRoot("candidate-plan-missing-goal")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("unreachable-symbolic-goal"),
            ]),
        ]
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "generate-candidate-plan",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                    "--pretty",
                ]
            )
        }

        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: ".xcircuite/runs/run-1/planning/problem-translation-audit.json")
        )
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.unsupportedGoalAtomCount == 1)
        #expect(audit.diagnostics.contains {
            $0.code == "unsupported-goal-atom"
                && $0.objectiveID == "drc-m1-width-1"
                && $0.goalAtom == "unreachable-symbolic-goal"
        })
        #expect(audit.nextActions.contains("add-candidate-action-effect-for-goal-atom"))
    }

    @Test func uncoveredIntentClausesBlockCandidatePlanBeforeGeneration() async throws {
        let root = try makeTemporaryRoot("candidate-plan-uncovered-intent-clause")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        var problem = makeDRCPlanningProblem()
        problem.sourceRefs[0] = XcircuitePlanningReference(
            refID: "drc-summary",
            kind: "human-intent",
            path: ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json",
            artifactID: "drc-summary",
            metadata: [
                "intentClauseIDs": .array([
                    .string("fix-width"),
                    .string("preserve-lvs"),
                ]),
            ]
        )
        var objective = problem.objectives[0]
        objective.evidence = [
            "symbolicGoalAtoms": .array([.string("rect-shape-created")]),
            "intentClauseIDs": .array([.string("fix-width")]),
        ]
        problem.objectives[0] = objective
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "generate-candidate-plan",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--run-id",
                    "run-1",
                    "--pretty",
                ]
            )
        }

        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: ".xcircuite/runs/run-1/planning/problem-translation-audit.json")
        )
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.intentClauseCount == 2)
        #expect(audit.coverageSummary.uncoveredIntentClauseCount == 1)
        #expect(audit.diagnostics.contains {
            $0.code == "intent-clause-uncovered"
                && $0.sourceRefID == "drc-summary"
                && $0.intentClauseID == "preserve-lvs"
        })
        #expect(audit.nextActions.contains("map-intent-clause-to-objective-constraint-or-action"))
    }

    private func makeDRCPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-1-drc-repair-problem",
            runID: "run-1",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "drc-summary",
                    kind: "drc-summary",
                    path: ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json",
                    artifactID: "drc-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: ".xcircuite/runs/run-1/stages/006-layout/raw/layout.gds"
                ),
            ],
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "drc-summary-current",
                    source: "test",
                    statement: "The DRC summary is current for the selected layout.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["drc-summary"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "drc-layout-edit-risk",
                    category: "layout-regression",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Selected layout edits must preserve signoff gates.",
                    affectedActionIDs: ["layout-add-rect-1"],
                    mitigationActions: ["native-drc", "native-lvs", "artifact-integrity"]
                ),
                XcircuitePlanningRiskClassification(
                    riskID: "unused-risk",
                    category: "unselected-action",
                    severity: "low",
                    scope: "candidate-plan",
                    description: "This risk belongs to an action that was not selected.",
                    affectedActionIDs: ["layout-other-action"]
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-m1-width-1",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["drc-summary"],
                    target: "no-active-violations-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair M1 width violation."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The candidate must pass DRC.",
                    sourceRefIDs: ["drc-summary"]
                ),
            ],
            actionDomainRefs: ["drc-signoff", "layout-edit", "lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-add-rect-1",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Apply a concrete layout edit family.",
                    sourceObjectiveIDs: ["drc-m1-width-1"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-drc", "native-lvs"],
                    parameterHints: ["ruleID": .string("M1.width")]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate must pass DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeStateProgressionPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-state-layout-problem",
            runID: "run-state",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "document-ref",
                    kind: "layout-document",
                    path: "layout/layout.json"
                ),
                XcircuitePlanningReference(
                    refID: "cell-ref",
                    kind: "layout-cell",
                    path: "layout/cells/top.json"
                ),
                XcircuitePlanningReference(
                    refID: "layer-ref",
                    kind: "layout-layer",
                    path: "technology/layers/m1.json"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "document-ref",
                    kind: "layout-document",
                    path: "layout/layout.json"
                ),
                XcircuitePlanningReference(
                    refID: "cell-ref",
                    kind: "layout-cell",
                    path: "layout/cells/top.json"
                ),
                XcircuitePlanningReference(
                    refID: "layer-ref",
                    kind: "layout-layer",
                    path: "technology/layers/m1.json"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "create-cell-objective",
                    kind: "create",
                    domain: "layout",
                    priority: "required",
                    sourceRefIDs: ["document-ref"],
                    target: "cell-exists",
                    description: "Create the target layout cell.",
                    evidence: [
                        "symbolicGoalAtoms": .array([
                            .string("cell-created"),
                            .string("cell-exists"),
                        ]),
                    ]
                ),
                XcircuitePlanningObjective(
                    objectiveID: "add-rect-objective",
                    kind: "create",
                    domain: "layout",
                    priority: "required",
                    sourceRefIDs: ["document-ref", "cell-ref", "layer-ref"],
                    target: "rect-shape-created",
                    description: "Create the first rectangle after the cell exists.",
                    evidence: [
                        "symbolicGoalAtoms": .array([
                            .string("rect-shape-created"),
                        ]),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["layout-edit"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "create-cell-step",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    reason: "Create the layout cell before shape edits.",
                    sourceObjectiveIDs: ["create-cell-objective"],
                    requiredInputRefs: ["document-ref"],
                    verificationGates: ["artifact-integrity"],
                    parameterHints: [
                        "satisfiedPreconditions": .array([
                            .string("unique-cell-id"),
                            .string("valid-cell-name"),
                        ]),
                        "symbolicEffects": .array([
                            .string("cell-exists"),
                        ]),
                    ]
                ),
                XcircuitePlanningCandidateAction(
                    actionID: "add-rect-step",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Add the first rectangle after the cell is available.",
                    sourceObjectiveIDs: ["add-rect-objective"],
                    requiredInputRefs: ["document-ref", "cell-ref", "layer-ref"],
                    verificationGates: ["artifact-integrity", "native-drc"],
                    parameterHints: [
                        "satisfiedPreconditions": .array([
                            .string("unique-shape-id"),
                            .string("positive-rect-size"),
                        ]),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "symbolic-state-progression", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Generated layout artifacts must be registered."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeGlobalFeedbackPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-global-feedback-symbolic-problem",
            runID: "run-global-feedback",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: "layout/input.gds"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: "layout/input.gds"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "layout-repair-objective",
                    kind: "repair",
                    domain: "layout",
                    priority: "error",
                    sourceRefIDs: ["layout-ref"],
                    target: "rect-shape-created",
                    description: "Select a layout repair action while respecting prior failed gates.",
                    evidence: [
                        "symbolicGoalAtoms": .array([
                            .string("rect-shape-created"),
                        ]),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["layout-edit"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "a-drc-sensitive-layout-repair",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Repair the layout using a DRC-sensitive edit family.",
                    sourceObjectiveIDs: ["layout-repair-objective"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["native-drc"],
                    parameterHints: [:]
                ),
                XcircuitePlanningCandidateAction(
                    actionID: "b-lvs-preserving-layout-repair",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Repair the layout using a candidate that does not match prior DRC feedback.",
                    sourceObjectiveIDs: ["layout-repair-objective"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["native-lvs"],
                    parameterHints: [:]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "feedback-aware-symbolic-ranking", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "DRC must pass."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "LVS must pass."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeLVSPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-2-lvs-repair-problem",
            runID: "run-2",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "lvs-summary",
                    kind: "lvs-summary",
                    path: ".xcircuite/runs/run-2/stages/008-lvs/raw/lvs-summary.json",
                    artifactID: "lvs-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/top.spice"
                ),
            ],
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "lvs-summary-current",
                    source: "test",
                    statement: "The LVS summary is current for the selected schematic.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["lvs-summary"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "lvs-policy-mutation-risk",
                    category: "policy-mutation",
                    severity: "high",
                    scope: "candidate-plan",
                    description: "Policy mutation changes LVS equivalence semantics.",
                    affectedActionIDs: ["lvs-policy-1"],
                    requiredApprovals: ["policy-repair-approval"],
                    mitigationActions: ["approval-gate", "native-lvs"]
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-model-policy-1",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: ["lvs-summary"],
                    target: "layout-and-schematic-equivalent-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair model policy mismatch."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "policy-repair-approval",
                    kind: "human-approval",
                    severity: "warning",
                    description: "Policy repair requires approval.",
                    sourceRefIDs: ["lvs-summary"]
                ),
            ],
            actionDomainRefs: ["lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "lvs-policy-1",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "implemented",
                    reason: "Resolve model equivalence through an auditable policy update.",
                    sourceObjectiveIDs: ["lvs-model-policy-1"],
                    requiredInputRefs: ["lvs-summary", "schematic-netlist-ref"],
                    verificationGates: ["approval-gate", "native-lvs"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Policy repair requires approval."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["approval-required"]
            )
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteCandidatePlanGeneratorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func rejectedPlanRecord(
        runID: String,
        problemID: String,
        planID: String,
        failedGateIDs: [String]
    ) -> XcircuiteRejectedPlanRecord {
        XcircuiteRejectedPlanRecord(
            rejectionID: "\(planID)-rejected",
            runID: runID,
            problemID: problemID,
            planID: planID,
            verificationMode: "post-waiver-edit",
            status: "rejected",
            sourceParameterCandidateIDs: [],
            failedStepIDs: ["apply-waiver-edit"],
            failedGateIDs: failedGateIDs,
            candidatePlanRef: XcircuiteFileReference(
                artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                path: ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/candidate-plan.json",
                kind: .other,
                format: .json
            ),
            planVerificationRef: XcircuiteFileReference(
                artifactID: XcircuitePlanningArtifactStore.planVerificationArtifactID,
                path: ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/plan-verification.json",
                kind: .other,
                format: .json
            ),
            artifactRefs: [],
            diagnostics: failedGateIDs.map {
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "POST_WAIVER_EDIT_GATE_FAILED",
                    message: "Post-waiver edit gate failed.",
                    gateID: $0
                )
            },
            nextActions: failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
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
