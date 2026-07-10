import Foundation
import LayoutAutoGen
import LayoutCore
import LayoutIO
import LayoutTech
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

extension XcircuiteCandidatePlanVerifierTests {
    @Test func artifactIntegrityBlocksWithoutProjectRoot() throws {
        let plan = makeSingleStepPlan(
            runID: "run-integrity-root",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-integrity-root")
        )

        let gate = try #require(verification.gateResults.first { $0.gateID == "artifact-integrity" })
        #expect(gate.status == "blocked")
        #expect(gate.diagnostics.contains {
            $0.code == "artifact-integrity-project-root-required"
        })
        #expect(verification.accepted == false)
    }

    @Test func artifactIntegrityFailsWhenCandidateArtifactDigestDoesNotMatchFile() throws {
        let root = try makeTemporaryRoot("candidate-plan-artifact-integrity-tamper")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-integrity-tamper", inProjectAt: root)
        let plan = makeSingleStepPlan(
            runID: "run-integrity-tamper",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        let candidatePlanRef = try XcircuitePlanningArtifactStore().persistCandidatePlan(
            plan,
            runID: "run-integrity-tamper",
            projectRoot: root
        )
        let candidatePlanURL = root.appending(path: candidatePlanRef.path)
        let originalData = try Data(contentsOf: candidatePlanURL)
        try Data(repeating: 0x58, count: originalData.count).write(to: candidatePlanURL)

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef,
            projectRoot: root
        )

        let gate = try #require(verification.gateResults.first { $0.gateID == "artifact-integrity" })
        #expect(gate.status == "failed")
        #expect(gate.diagnostics.contains {
            $0.code == "artifact-integrity-sha256-mismatch"
        })
        #expect(gate.diagnostics.contains {
            $0.message.contains("actualSHA256=") && $0.message.contains("expectedSHA256=")
        })
        #expect(verification.accepted == false)
    }

    @Test func unsupportedPlannerOperationBlocksPlanVerification() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-1",
            generatedAt: "2026-06-20T00:00:00Z"
        )
        var plan = makeSingleStepPlan(
            runID: "run-1",
            domainID: "layout-edit",
            operationID: "layout.teleport-shape",
            maturity: "implemented"
        )
        plan.steps[0].readiness = "ready"
        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-1"),
            actionDomainSnapshot: snapshot
        )

        #expect(verification.accepted == false)
        #expect(verification.stepResults.first?.status == "blocked")
        #expect(verification.diagnostics.contains { $0.code == "unsupported-operation" })
        #expect(verification.nextActions.contains("revise-plan-to-supported-action"))
    }

    @Test func rejectedPlanDiagnosticClassifierSeparatesRootCausesForAgentFeedback() throws {
        let verification = XcircuitePlanVerification(
            problemID: "run-taxonomy-problem",
            planID: "run-taxonomy-plan",
            runID: "run-taxonomy",
            verificationMode: "post-execution",
            candidatePlanRef: candidatePlanRef(runID: "run-taxonomy"),
            stepResults: [
                XcircuitePlanVerificationStepResult(
                    stepID: "step-unsupported",
                    order: 0,
                    actionID: "unsupported-action",
                    domainID: "layout-edit",
                    operationID: "layout.teleport-shape",
                    status: "blocked",
                    gateIDs: ["action-domain-binding"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "unsupported-operation",
                            message: "Operation is not supported by the retained action domain.",
                            stepID: "step-unsupported"
                        ),
                    ]
                ),
                XcircuitePlanVerificationStepResult(
                    stepID: "step-missing-input",
                    order: 1,
                    actionID: "missing-input-action",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    status: "blocked",
                    gateIDs: ["action-domain-binding"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "unbound-operation-input-refs",
                            message: "missing-input-refs:document-ref,layer-ref",
                            stepID: "step-missing-input"
                        ),
                    ]
                ),
            ],
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: true,
                    status: "blocked",
                    sourceStepIDs: ["step-unsupported"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "external-tool-readiness-blocked",
                            message: "Magic executable is missing from the configured PDK toolchain.",
                            gateID: "native-drc"
                        ),
                    ]
                ),
                XcircuitePlanVerificationGateResult(
                    gateID: "artifact-integrity",
                    required: true,
                    status: "failed",
                    sourceStepIDs: ["step-missing-input"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "artifact-integrity-missing",
                            message: "Artifact manifest has stale hash and missing byte count.",
                            gateID: "artifact-integrity"
                        ),
                    ]
                ),
                XcircuitePlanVerificationGateResult(
                    gateID: "simulation-metric-gate",
                    required: true,
                    status: "failed",
                    sourceStepIDs: ["step-missing-input"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                            message: "Candidate measurement missed target.",
                            gateID: "simulation-metric-gate"
                        ),
                    ]
                ),
            ],
            correctnessGateResults: [
                XcircuitePlanningCorrectnessGateResult(
                    gateID: "planner-replay",
                    status: "blocked",
                    summary: "Objective goal atom is missing.",
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "missing-goal-atom",
                            message: "missing-goal-atom:objective-1:goal(layout-clean)",
                            gateID: "planner-replay"
                        ),
                    ],
                    nextActions: ["revise-plan-to-cover-goals:objective-1"]
                ),
            ],
            artifactRefs: [
                XcircuiteFileReference(
                    artifactID: "stale-layout-artifact",
                    path: ".xcircuite/runs/run-taxonomy/layout.gds",
                    kind: .other,
                    format: .json
                ),
            ],
            missingGoalAtoms: ["goal(layout-clean)"],
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                    message: "Candidate measurement missed target.",
                    gateID: "simulation-metric-gate"
                ),
                XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "calibration-uncertainty",
                    message: "Cost calibration confidence is low because posterior variance remains high.",
                    gateID: "calibration-confidence"
                ),
            ],
            accepted: false,
            nextActions: [
                "revise-plan-to-supported-action",
                "provide-input-ref:document-ref",
                "check-external-tool-readiness:native-drc",
                "refresh-stale-artifact:stale-layout-artifact",
                "repair-verification-gate:simulation-metric-gate",
                "collect-more-calibration-observations",
                "revise-plan-to-cover-goals:objective-1",
            ]
        )

        let classifications = XcircuiteRejectedPlanDiagnosticClassifier().classify(
            verification: verification,
            status: "blocked"
        )
        let classes = Set(classifications.map { $0.diagnosticClass })

        #expect(classes == [
            XcircuiteRejectedPlanDiagnosticClass.unsupportedOperation,
            XcircuiteRejectedPlanDiagnosticClass.missingInput,
            XcircuiteRejectedPlanDiagnosticClass.failedVerificationGate,
            XcircuiteRejectedPlanDiagnosticClass.externalToolBlocker,
            XcircuiteRejectedPlanDiagnosticClass.staleArtifact,
            XcircuiteRejectedPlanDiagnosticClass.objectiveRegression,
            XcircuiteRejectedPlanDiagnosticClass.calibrationUncertainty,
        ])
        let unsupported = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.unsupportedOperation
        })
        #expect(unsupported.failedStepIDs.contains("step-unsupported"))
        #expect(unsupported.reasonCodes.contains("unsupported-operation"))
        #expect(unsupported.nextActions.contains("revise-plan-to-supported-action"))

        let missingInput = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.missingInput
        })
        #expect(missingInput.failedStepIDs.contains("step-missing-input"))
        #expect(missingInput.reasonCodes.contains("unbound-operation-input-refs"))
        #expect(missingInput.nextActions.contains("provide-input-ref:document-ref"))

        let failedGate = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.failedVerificationGate
        })
        #expect(failedGate.failedGateIDs.contains("simulation-metric-gate"))
        #expect(failedGate.reasonCodes.contains("gate_status_failed"))

        let externalTool = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.externalToolBlocker
        })
        #expect(externalTool.failedGateIDs.contains("native-drc"))
        #expect(externalTool.reasonCodes.contains("external-tool-readiness-blocked"))

        let staleArtifact = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.staleArtifact
        })
        #expect(staleArtifact.failedGateIDs.contains("artifact-integrity"))
        #expect(staleArtifact.artifactIDs.contains("stale-layout-artifact"))

        let objectiveRegression = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.objectiveRegression
        })
        #expect(objectiveRegression.reasonCodes.contains("missing_goal_atoms"))
        #expect(objectiveRegression.diagnosticCodes.contains("SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE"))

        let calibrationUncertainty = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.calibrationUncertainty
        })
        #expect(calibrationUncertainty.reasonCodes.contains("calibration-uncertainty"))
        #expect(calibrationUncertainty.failedGateIDs.contains("calibration-confidence"))
        #expect(calibrationUncertainty.nextActions.contains("collect-more-calibration-observations"))

        let record = XcircuiteRejectedPlanRecord(
            rejectionID: "run-taxonomy-rejection",
            runID: verification.runID,
            problemID: verification.problemID,
            planID: verification.planID,
            verificationMode: verification.verificationMode,
            status: "blocked",
            sourceParameterCandidateIDs: ["candidate-taxonomy"],
            failedStepIDs: verification.stepResults.map { $0.stepID },
            failedGateIDs: verification.gateResults.map { $0.gateID },
            candidatePlanRef: verification.candidatePlanRef,
            planVerificationRef: candidatePlanRef(runID: "run-taxonomy"),
            artifactRefs: verification.artifactRefs,
            diagnostics: verification.diagnostics,
            diagnosticClassifications: classifications,
            nextActions: verification.nextActions
        )
        let summary = XcircuiteRejectedPlanFeedbackBuilder().makeFeedbackSummary(
            runID: "run-taxonomy",
            path: ".xcircuite/runs/run-taxonomy/planning/rejected-plans.jsonl",
            records: [record]
        )
        let candidateFeedback = try #require(summary.candidateFeedback.first)
        #expect(candidateFeedback.diagnosticClasses.contains("unsupported_operation"))
        #expect(candidateFeedback.diagnosticClasses.contains("objective_regression"))
        #expect(candidateFeedback.diagnosticClasses.contains("calibration_uncertainty"))
        #expect(summary.diagnosticClassCounts["unsupported_operation"] == 1)
        #expect(summary.diagnosticClassCounts["missing_input"] == 1)
        #expect(summary.diagnosticClassCounts["failed_verification_gate"] == 1)
        #expect(summary.diagnosticClassCounts["external_tool_blocker"] == 1)
        #expect(summary.diagnosticClassCounts["stale_artifact"] == 1)
        #expect(summary.diagnosticClassCounts["objective_regression"] == 1)
        #expect(summary.diagnosticClassCounts["calibration_uncertainty"] == 1)
    }

    @Test func rejectedPlanDiagnosticClassifierTreatsDigestCurrentnessFailuresAsStaleArtifacts() throws {
        let verification = XcircuitePlanVerification(
            problemID: "run-currentness-problem",
            planID: "run-currentness-plan",
            runID: "run-currentness",
            verificationMode: "pre-execution",
            candidatePlanRef: candidatePlanRef(runID: "run-currentness"),
            stepResults: [],
            gateResults: [],
            correctnessGateResults: [],
            artifactRefs: [
                XcircuiteFileReference(
                    artifactID: "planning-problem",
                    path: ".xcircuite/runs/run-currentness/planning/problem.json",
                    kind: .other,
                    format: .json
                ),
            ],
            missingGoalAtoms: [],
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "artifact-currentness-failed",
                    message: "Digest and byteCount no longer match the recorded reference."
                ),
            ],
            accepted: false,
            nextActions: ["refresh-artifact:planning-problem"]
        )

        let classifications = XcircuiteRejectedPlanDiagnosticClassifier().classify(
            verification: verification,
            status: "rejected"
        )

        let staleArtifact = try #require(classifications.first {
            $0.diagnosticClass == XcircuiteRejectedPlanDiagnosticClass.staleArtifact
        })
        #expect(staleArtifact.reasonCodes.contains("artifact-currentness-failed"))
        #expect(staleArtifact.artifactIDs.contains("planning-problem"))
        #expect(staleArtifact.nextActions == ["refresh-artifact:planning-problem"])
    }

    @Test func rejectedPlanRecordRejectsMissingDiagnosticClassifications() throws {
        let record = XcircuiteRejectedPlanRecord(
            rejectionID: "incomplete-rejection",
            runID: "run-incomplete",
            problemID: "problem-incomplete",
            planID: "plan-incomplete",
            verificationMode: "post-execution",
            status: "rejected",
            sourceParameterCandidateIDs: ["candidate-incomplete"],
            failedStepIDs: ["step-incomplete"],
            failedGateIDs: ["native-drc"],
            candidatePlanRef: candidatePlanRef(runID: "run-incomplete"),
            planVerificationRef: candidatePlanRef(runID: "run-incomplete"),
            artifactRefs: [],
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "NATIVE_DRC_FAILED",
                    message: "Native DRC failed.",
                    stepID: "step-incomplete",
                    gateID: "native-drc"
                ),
            ],
            diagnosticClassifications: [
                XcircuiteRejectedPlanDiagnosticClassification(
                    classificationID: "plan-incomplete:failed_verification_gate",
                    diagnosticClass: .failedVerificationGate,
                    severity: "error",
                    reasonCodes: ["NATIVE_DRC_FAILED"],
                    status: "rejected",
                    planID: "plan-incomplete",
                    failedStepIDs: ["step-incomplete"],
                    failedGateIDs: ["native-drc"],
                    diagnosticCodes: ["NATIVE_DRC_FAILED"],
                    nextActions: ["repair-verification-gate:native-drc"]
                ),
            ],
            nextActions: ["repair-verification-gate:native-drc"]
        )
        let encoded = try JSONEncoder().encode(record)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "diagnosticClassifications")
        let incompleteData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(XcircuiteRejectedPlanRecord.self, from: incompleteData)
        }
    }

    @Test func maturityMismatchBlocksPlanVerification() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-1",
            generatedAt: "2026-06-20T00:00:00Z"
        )
        let plan = makeSingleStepPlan(
            runID: "run-1",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "planned"
        )
        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-1"),
            actionDomainSnapshot: snapshot
        )

        #expect(verification.accepted == false)
        #expect(verification.stepResults.first?.status == "blocked")
        #expect(verification.diagnostics.contains { $0.code == "action-domain-maturity-mismatch" })
        #expect(verification.nextActions.contains("refresh-action-domain-snapshot"))
    }

    @Test func symbolicStepEvaluationRecordsSatisfiedPreconditionsAndStateTransition() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-1",
            generatedAt: "2026-06-20T00:00:00Z"
        )
        var plan = makeSingleStepPlan(
            runID: "run-1",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        plan.steps[0].requiredInputRefs = ["document-ref", "cell-ref", "layer-ref"]
        plan.steps[0].parameterHints = [
            "satisfiedPreconditions": .array([
                .string("cell-exists"),
                .string("unique-shape-id"),
                .string("positive-rect-size"),
            ]),
        ]
        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-1"),
            actionDomainSnapshot: snapshot
        )

        let symbolicEvaluation = try #require(verification.stepResults.first?.symbolicEvaluation)
        #expect(symbolicEvaluation.bindingStatus == "bound")
        #expect(symbolicEvaluation.boundOperationInputRefs == ["document-ref", "cell-ref", "layer-ref"])
        #expect(symbolicEvaluation.unboundOperationInputRefs == [])
        #expect(symbolicEvaluation.satisfiedPreconditions == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(symbolicEvaluation.unsatisfiedPreconditions == [])
        #expect(symbolicEvaluation.stateBefore.contains("cell-exists"))
        #expect(symbolicEvaluation.stateAfter.contains("rect-shape-created"))
        #expect(symbolicEvaluation.stateAfter.contains("optional-net-assigned"))
        #expect(symbolicEvaluation.stateAfter.contains("artifact:layout-document"))
    }

    @Test func verifierBlocksReadyStepWithUnboundActionDomainInputRefs() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-1",
            generatedAt: "2026-06-20T00:00:00Z"
        )
        var plan = makeSingleStepPlan(
            runID: "run-1",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        plan.steps[0].requiredInputRefs = ["document-ref", "cell-ref"]
        plan.steps[0].parameterHints = [
            "satisfiedPreconditions": .array([
                .string("cell-exists"),
                .string("unique-shape-id"),
                .string("positive-rect-size"),
            ]),
        ]

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-1"),
            actionDomainSnapshot: snapshot
        )

        let step = try #require(verification.stepResults.first)
        #expect(verification.accepted == false)
        #expect(step.status == "blocked")
        #expect(step.symbolicEvaluation?.bindingStatus == "partially-bound")
        #expect(step.symbolicEvaluation?.unboundOperationInputRefs == ["layer-ref"])
        #expect(step.diagnostics.contains { $0.code == "unbound-operation-input-refs" })
        #expect(!step.diagnostics.contains { $0.code == "unproven-operation-preconditions" })
        #expect(verification.nextActions.contains("bind-operation-input-ref:layer-ref"))
        let correctnessGates = Dictionary(
            uniqueKeysWithValues: verification.correctnessGateResults.map { ($0.gateID, $0.status) }
        )
        #expect(correctnessGates["action-domain-binding"] == "blocked")
    }

    @Test func verifierBlocksReadyStepWithUnprovenActionDomainPreconditions() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-1",
            generatedAt: "2026-06-20T00:00:00Z"
        )
        var plan = makeSingleStepPlan(
            runID: "run-1",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        plan.steps[0].requiredInputRefs = ["document-ref", "cell-ref", "layer-ref"]

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-1"),
            actionDomainSnapshot: snapshot
        )

        let step = try #require(verification.stepResults.first)
        #expect(verification.accepted == false)
        #expect(step.status == "blocked")
        #expect(step.symbolicEvaluation?.bindingStatus == "preconditions-unproven")
        #expect(step.symbolicEvaluation?.unboundOperationInputRefs == [])
        #expect(step.symbolicEvaluation?.unsatisfiedPreconditions == [
            "cell-exists",
            "unique-shape-id",
            "positive-rect-size",
        ])
        #expect(!step.diagnostics.contains { $0.code == "unbound-operation-input-refs" })
        #expect(step.diagnostics.contains { $0.code == "unproven-operation-preconditions" })
        #expect(verification.nextActions.contains("prove-operation-precondition:cell-exists"))
        #expect(verification.nextActions.contains("prove-operation-precondition:unique-shape-id"))
        #expect(verification.nextActions.contains("prove-operation-precondition:positive-rect-size"))
        let correctnessGates = Dictionary(
            uniqueKeysWithValues: verification.correctnessGateResults.map { ($0.gateID, $0.status) }
        )
        #expect(correctnessGates["action-domain-binding"] == "blocked")
    }

    @Test func verificationBlocksExternallyGeneratedPlanWithMissingGoalAtoms() async throws {
        let root = try makeTemporaryRoot("candidate-plan-verify-missing-goal")
        defer { removeTemporaryRoot(root) }
        var problem = makeDRCPlanningProblem()
        problem.runID = "run-goal"
        problem.problemID = "run-goal-problem"
        problem.objectives[0].objectiveID = "objective-1"
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([
                .string("unreachable-symbolic-goal"),
            ]),
        ]
        try prepareRun(root: root, runID: "run-goal", problem: problem)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeSingleStepPlan(
                runID: "run-goal",
                domainID: "layout-edit",
                operationID: "layout.add-rect",
                maturity: "implemented"
            ),
            runID: "run-goal",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(runID: "run-goal"),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.accepted == false)
        #expect(result.nextActions.contains("revise-plan-to-cover-goals:objective-1"))
        let verification = try XcircuitePackageStore().readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: result.planVerificationArtifact.path)
        )
        #expect(verification.goalCoverageStatus == "missing")
        #expect(verification.missingGoalAtoms == ["objective-1:unreachable-symbolic-goal"])
        #expect(verification.diagnostics.contains { $0.code == "missing-goal-atom" })
        let coverage = try #require(verification.goalCoverage.first)
        #expect(coverage.objectiveID == "objective-1")
        #expect(coverage.status == "missing")
        #expect(coverage.missingGoalAtoms == ["unreachable-symbolic-goal"])
    }

}
