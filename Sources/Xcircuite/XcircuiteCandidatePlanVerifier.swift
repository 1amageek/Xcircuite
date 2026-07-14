import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel
import CircuiteFoundation

public struct XcircuiteCandidatePlanVerifier: Sendable {
    let workspaceStore: XcircuiteWorkspaceStore
    let artifactStore: XcircuitePlanningArtifactStore
    let artifactBuilder: StageArtifactReferenceBuilder
    let layoutDocumentSerializer: LayoutDocumentSerializer
    let symbolicPlannerContract: XcircuiteSymbolicPlannerContract
    let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactBuilder = StageArtifactReferenceBuilder()
        self.layoutDocumentSerializer = LayoutDocumentSerializer()
        self.symbolicPlannerContract = XcircuiteSymbolicPlannerContract()
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func verifyCandidatePlan(
        request: XcircuiteCandidatePlanVerificationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanVerificationResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let candidatePlanRef = try requiredCandidatePlanReference(
            explicitPath: request.candidatePlanPath,
            artifactID: request.candidatePlanArtifactID ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        guard let candidatePlanURL = fileReferenceVerifier.resolvedURL(
            for: candidatePlanRef,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: candidatePlanRef.path,
                reason: "candidate plan path cannot be resolved inside the project root."
            )
        }
        let plan = try workspaceStore.readJSON(
            XcircuiteCandidatePlan.self,
            from: candidatePlanURL
        )
        guard plan.runID == request.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: request.runID,
                actual: plan.runID
            )
        }
        let planningProblem = try loadPlanningProblem(
            for: plan,
            projectRoot: projectRoot
        )
        let planningProblemValidationRef = manifest.artifacts.first {
            $0.artifactID == XcircuitePlanningArtifactStore.planningProblemValidationArtifactID
        }
        let approvals = try workspaceStore.loadApprovals(
            runID: request.runID,
            inProjectAt: projectRoot
        )
        let actionDomainContext = try loadOrPersistActionDomainSnapshot(
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )

        let verification: XcircuitePlanVerification
        if request.verificationMode == "post-execution" {
            verification = try await makePostExecutionPlanVerification(
                plan: plan,
                candidatePlanRef: candidatePlanRef,
                actionDomainSnapshotRef: actionDomainContext.reference,
                actionDomainSnapshot: actionDomainContext.snapshot,
                planningProblemValidationRef: planningProblemValidationRef,
                planningProblem: planningProblem,
                approvals: approvals,
                manifest: manifest,
                projectRoot: projectRoot
            )
        } else {
            verification = makePlanVerification(
                plan: plan,
                candidatePlanRef: candidatePlanRef,
                actionDomainSnapshotRef: actionDomainContext.reference,
                actionDomainSnapshot: actionDomainContext.snapshot,
                planningProblemValidationRef: planningProblemValidationRef,
                planningProblem: planningProblem,
                approvals: approvals,
                verificationMode: request.verificationMode,
                projectRoot: projectRoot
            )
        }
        let verificationRef = try artifactStore.persistPlanVerification(
            verification,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let status = verificationStatus(for: verification)
        let rejectedPlansRef = try persistRejectedPlanIfNeeded(
            status: status,
            verification: verification,
            candidatePlanRef: candidatePlanRef,
            verificationRef: verificationRef,
            projectRoot: projectRoot
        )
        try appendActionRecord(
            verification: verification,
            candidatePlanRef: candidatePlanRef,
            verificationRef: verificationRef,
            rejectedPlansRef: rejectedPlansRef,
            projectRoot: projectRoot
        )

        return XcircuiteCandidatePlanVerificationResult(
            status: status,
            runID: request.runID,
            problemID: plan.problemID,
            planID: plan.planID,
            accepted: verification.accepted,
            candidatePlanPath: candidatePlanRef.path,
            planVerificationArtifact: try requireFoundationArtifactReference(
                verificationRef,
                field: "plan-verification"
            ),
            rejectedPlansArtifact: try rejectedPlansRef.map {
                try requireFoundationArtifactReference($0, field: "rejected-plans")
            },
            nextActions: verification.nextActions
        )
    }

    public func makePlanVerification(
        plan: XcircuiteCandidatePlan,
        candidatePlanRef: XcircuiteFileReference,
        actionDomainSnapshotRef: XcircuiteFileReference? = nil,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot? = nil,
        planningProblemValidationRef: XcircuiteFileReference? = nil,
        planningProblem: XcircuiteCircuitPlanningProblem? = nil,
        approvals: [XcircuiteApprovalRecord] = [],
        verificationMode: String = "preflight",
        projectRoot: URL? = nil
    ) -> XcircuitePlanVerification {
        let symbolicSummary = symbolicVerificationSummary(
            for: plan,
            actionDomainSnapshot: actionDomainSnapshot,
            planningProblem: planningProblem
        )
        let stepResults = symbolicSummary.stepResults
        let goalCoverage = goalCoverage(
            for: planningProblem?.objectives ?? [],
            finalSymbolicState: symbolicSummary.finalSymbolicState
        )
        let missingGoalAtoms = missingGoalAtomRefs(from: goalCoverage)
        let riskReviewer = XcircuiteCandidatePlanRiskReviewer()
        let riskReviews = riskReviewer.riskReviews(for: plan, approvals: approvals)
        let legacyArtifactCandidates = [candidatePlanRef]
            + [actionDomainSnapshotRef, planningProblemValidationRef].compactMap { $0 }
        let invalidArtifactReferences = legacyArtifactCandidates.filter {
            foundationArtifactReference($0) == nil
        }
        let artifactReferences = uniqueArtifactReferences(
            legacyArtifactCandidates.compactMap(foundationArtifactReference)
        )
        let planningProblemValidationArtifact = planningProblemValidationRef.flatMap(foundationArtifactReference)
        let actionDomainSnapshotArtifact = actionDomainSnapshotRef.flatMap(foundationArtifactReference)
        let gateResults = makeGateResults(
            plan: plan,
            stepResults: stepResults,
            riskReviews: riskReviews,
            artifactRefs: legacyArtifactCandidates,
            projectRoot: projectRoot
        )
        let artifactProjectionDiagnostics = invalidArtifactReferences.map {
            XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "invalid-artifact-reference",
                message: "Artifact \($0.path) cannot be represented as a Foundation artifact reference."
            )
        }
        let diagnostics = planDiagnostics(for: plan, stepResults: stepResults)
            + riskReviewer.blockingDiagnostics(from: riskReviews)
            + goalCoverageDiagnostics(from: goalCoverage)
            + gateResults.flatMap(\.diagnostics)
            + artifactProjectionDiagnostics
        let nextActions = unique(
            makeNextActions(
                plan: plan,
                stepResults: stepResults,
                gateResults: gateResults,
                riskReviews: riskReviews,
                goalCoverage: goalCoverage
            ) + artifactProjectionDiagnostics.flatMap { self.nextActions(for: $0) }
        )
        let accepted = stepResults.allSatisfy { $0.status == "preflight-passed" }
            && gateResults.filter(\.required).allSatisfy { $0.status == "passed" }
            && !riskReviewer.blocksExecution(riskReviews)
            && !goalCoverage.contains(where: { $0.status == "missing" })
            && invalidArtifactReferences.isEmpty
            && plan.unresolvedObjectives.isEmpty
        let correctnessGateResults = makeCorrectnessGateResults(
            plan: plan,
            verificationMode: verificationMode,
            planningProblem: planningProblem,
            planningProblemValidationArtifact: planningProblemValidationArtifact,
            actionDomainSnapshotArtifact: actionDomainSnapshotArtifact,
            stepResults: stepResults,
            gateResults: gateResults,
            goalCoverage: goalCoverage,
            artifactReferences: artifactReferences,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: nextActions
        )

        return XcircuitePlanVerification(
            problemID: plan.problemID,
            planID: plan.planID,
            runID: plan.runID,
            verificationMode: verificationMode,
            candidatePlanRef: candidatePlanRef,
            stepResults: stepResults,
            gateResults: gateResults,
            correctnessGateResults: correctnessGateResults,
            riskReviews: riskReviews,
            artifactRefs: legacyArtifactCandidates,
            initialSymbolicState: symbolicSummary.initialSymbolicState,
            finalSymbolicState: symbolicSummary.finalSymbolicState,
            goalCoverageStatus: goalCoverageStatus(from: goalCoverage),
            goalCoverage: goalCoverage,
            missingGoalAtoms: missingGoalAtoms,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: nextActions
        )
    }
}
