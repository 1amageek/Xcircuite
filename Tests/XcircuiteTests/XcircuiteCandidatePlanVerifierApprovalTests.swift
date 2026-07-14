import Foundation
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
    @Test func missingInputReferenceBlocksPlanVerification() throws {
        var problem = makeDRCPlanningProblem()
        problem.initialStateRefs = []
        let plan = try XcircuiteCandidatePlanGenerator().makeCandidatePlan(
            problem: problem,
            problemPath: ".xcircuite/runs/run-1/planning/problem.json"
        )
        let candidatePlanRef = XcircuiteFileReference(
            artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            path: ".xcircuite/runs/run-1/planning/candidate-plan.json",
            kind: .other,
            format: .json,
            sha256: "abc",
            byteCount: 12,
            producedByRunID: "run-1"
        )

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef
        )

        #expect(verification.accepted == false)
        #expect(verification.stepResults.first?.status == "blocked")
        #expect(verification.diagnostics.contains { $0.code == "missing-input-refs" })
        #expect(verification.nextActions.contains("provide-input-ref:layout-ref"))
    }

    @Test func lvsPolicyRepairPlanBlocksAcceptanceOnApprovalGate() throws {
        let plan = try XcircuiteCandidatePlanGenerator().makeCandidatePlan(
            problem: makeLVSPlanningProblem(),
            problemPath: ".xcircuite/runs/run-2/planning/problem.json"
        )
        let candidatePlanRef = XcircuiteFileReference(
            artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            path: ".xcircuite/runs/run-2/planning/candidate-plan.json",
            kind: .other,
            format: .json,
            sha256: "abc",
            byteCount: 12,
            producedByRunID: "run-2"
        )

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef
        )

        #expect(verification.accepted == false)
        #expect(verification.stepResults.first?.status == "preflight-passed")
        #expect(verification.gateResults.contains { $0.gateID == "approval-gate" && $0.status == "blocked" })
        #expect(verification.nextActions.contains("request-human-approval:approval-gate"))
        #expect(verification.nextActions.contains("run-verification-gate:native-lvs"))
    }

    @Test func riskRequiredApprovalAddsReviewAndSyntheticApprovalGate() throws {
        var plan = makeSingleStepPlan(
            runID: "run-risk",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        plan.riskClassifications = [
            XcircuitePlanningRiskClassification(
                riskID: "policy-mutation-risk",
                category: "lvs-policy",
                severity: "high",
                scope: "candidate-plan",
                description: "Policy mutation requires explicit review before execution.",
                affectedObjectiveIDs: ["objective-1"],
                affectedActionIDs: ["candidate-action-1"],
                requiredApprovals: ["policy-repair-approval"],
                mitigationActions: ["approval-gate", "native-lvs"]
            ),
        ]

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef(runID: "run-risk")
        )

        #expect(verification.accepted == false)
        #expect(verification.riskReviews.map(\.riskID) == ["policy-mutation-risk"])
        #expect(verification.riskReviews.first?.status == "approval-required")
        #expect(verification.riskReviews.first?.approvalReviews.map(\.status) == ["missing"])
        #expect(verification.riskReviews.first?.affectedStepIDs == ["run-risk-candidate-plan-1-step-1"])
        #expect(verification.gateResults.contains {
            $0.gateID == "approval-gate" && $0.status == "blocked"
        })
        #expect(verification.diagnostics.contains { $0.code == "risk-approval-required" })
        #expect(verification.nextActions.contains("request-human-approval:policy-repair-approval"))
    }

    @Test func recordedRiskApprovalPassesSyntheticApprovalGate() throws {
        let root = try makeTemporaryRoot("candidate-plan-approved-risk-integrity")
        defer { removeTemporaryRoot(root) }
        let store = XcircuiteWorkspaceStore()
        try store.createWorkspace(at: root)
        try store.createRunDirectory(for: "run-risk-approved", inProjectAt: root)
        var plan = makeSingleStepPlan(
            runID: "run-risk-approved",
            domainID: "layout-edit",
            operationID: "layout.add-rect",
            maturity: "implemented"
        )
        plan.riskClassifications = [
            XcircuitePlanningRiskClassification(
                riskID: "policy-mutation-risk",
                category: "lvs-policy",
                severity: "high",
                scope: "candidate-plan",
                description: "Policy mutation requires explicit review before execution.",
                affectedObjectiveIDs: ["objective-1"],
                affectedActionIDs: ["candidate-action-1"],
                requiredApprovals: ["policy-repair-approval"],
                mitigationActions: ["approval-gate", "native-lvs"]
            ),
        ]
        let candidatePlanRef = try XcircuitePlanningArtifactStore().persistCandidatePlan(
            plan,
            runID: "run-risk-approved",
            projectRoot: root
        )
        let approval = XcircuiteApprovalRecord(
            runID: "run-risk-approved",
            stageID: "policy-repair-approval",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "Approved for policy repair regression."
        )

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: plan,
            candidatePlanRef: candidatePlanRef,
            approvals: [approval],
            projectRoot: root
        )

        #expect(verification.accepted)
        #expect(verification.riskReviews.first?.status == "approved")
        #expect(verification.riskReviews.first?.approvalReviews.map(\.status) == ["approved"])
        #expect(verification.gateResults.contains {
            $0.gateID == "approval-gate" && $0.status == "passed"
        })
        #expect(verification.diagnostics.contains { $0.code == "risk-approval-required" } == false)
        #expect(verification.nextActions.contains("request-human-approval:policy-repair-approval") == false)
    }

}
