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
    let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactBuilder = StageArtifactReferenceBuilder()
        self.layoutDocumentSerializer = LayoutDocumentSerializer()
        self.symbolicPlannerContract = XcircuiteSymbolicPlannerContract()
        self.artifactVerifier = artifactVerifier
    }

    public func verifyCandidatePlan(
        request: XcircuiteCandidatePlanVerificationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanVerificationResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let ledger = try await workspaceStore.loadAttestedRunLedger(runID: request.runID)
        let manifest = ledger.runManifest
        let expectedCandidatePlanArtifactID: String?
        if let artifactID = request.candidatePlanArtifactID {
            expectedCandidatePlanArtifactID = artifactID
        } else if request.candidatePlanPath == nil {
            let generatedReferences = XcircuitePlanningArtifactStore
                .generatedCandidatePlanReferences(in: manifest)
            guard generatedReferences.count <= 1 else {
                throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                    path: XcircuitePlanningArtifactStore.generatedCandidatePlanDirectory,
                    reason: "multiple generated candidate plans are retained; specify an artifact ID or path."
                )
            }
            expectedCandidatePlanArtifactID = generatedReferences.first?.artifactID
                ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID
        } else {
            expectedCandidatePlanArtifactID = nil
        }
        let currentCandidatePlanRef = try requiredCandidatePlanReference(
            explicitPath: request.candidatePlanPath,
            artifactID: expectedCandidatePlanArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let plan: XcircuiteCandidatePlan = try await decodeRetainedArtifact(
            currentCandidatePlanRef,
            as: XcircuiteCandidatePlan.self
        )
        guard plan.runID == request.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: request.runID,
                actual: plan.runID
            )
        }
        let candidatePlanRef = try await artifactStore.persistCandidatePlanSnapshot(
            plan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let planningProblem = try await loadPlanningProblem(
            for: plan,
            manifest: manifest
        )
        let planningProblemValidationRef = manifest.artifacts.first {
            $0.artifactID == XcircuitePlanningArtifactStore.planningProblemValidationArtifactID
        }
        let approvals = try await validatedRiskApprovals(
            in: ledger,
            for: plan,
            candidatePlanReference: candidatePlanRef
        )
        let actionDomainContext = try await loadOrPersistActionDomainSnapshot(
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
        let verificationRef = try await artifactStore.persistPlanVerification(
            verification,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let status = verificationStatus(for: verification)
        let rejectedPlansRef = try await persistRejectedPlanIfNeeded(
            status: status,
            verification: verification,
            candidatePlanRef: candidatePlanRef,
            verificationRef: verificationRef,
            projectRoot: projectRoot
        )
        try await appendActionRecord(
            verification: verification,
            candidatePlanRef: candidatePlanRef,
            verificationRef: verificationRef
        )

        return XcircuiteCandidatePlanVerificationResult(
            status: status,
            runID: request.runID,
            problemID: plan.problemID,
            planID: plan.planID,
            accepted: verification.accepted,
            candidatePlanPath: candidatePlanRef.path,
            planVerificationArtifact: verificationRef,
            rejectedPlansArtifact: rejectedPlansRef,
            nextActions: verification.nextActions
        )
    }

    public func makePlanVerification(
        plan: XcircuiteCandidatePlan,
        candidatePlanRef: ArtifactReference,
        actionDomainSnapshotRef: ArtifactReference? = nil,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot? = nil,
        planningProblemValidationRef: ArtifactReference? = nil,
        planningProblem: XcircuiteCircuitPlanningProblem? = nil,
        approvals: [FlowApprovalRecord] = [],
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
        let artifactReferences = uniqueArtifactReferences(
            [candidatePlanRef]
            + [actionDomainSnapshotRef, planningProblemValidationRef].compactMap { $0 }
        )
        let planningProblemValidationArtifact = planningProblemValidationRef
        let actionDomainSnapshotArtifact = actionDomainSnapshotRef
        let gateResults = makeGateResults(
            plan: plan,
            stepResults: stepResults,
            riskReviews: riskReviews,
            artifactRefs: artifactReferences,
            projectRoot: projectRoot
        )
        let diagnostics = planDiagnostics(for: plan, stepResults: stepResults)
            + riskReviewer.blockingDiagnostics(from: riskReviews)
            + goalCoverageDiagnostics(from: goalCoverage)
            + gateResults.flatMap(\.diagnostics)
        let nextActions = unique(
            makeNextActions(
                plan: plan,
                stepResults: stepResults,
                gateResults: gateResults,
                riskReviews: riskReviews,
                goalCoverage: goalCoverage
            )
        )
        let accepted = stepResults.allSatisfy { $0.status == "preflight-passed" }
            && gateResults.filter(\.required).allSatisfy { $0.status == "passed" }
            && !riskReviewer.blocksExecution(riskReviews)
            && !goalCoverage.contains(where: { $0.status == "missing" })
            && plan.unresolvedObjectives.isEmpty
        let correctnessGateResults = makeCorrectnessGateResults(
            plan: plan,
            candidatePlanArtifact: candidatePlanRef,
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
            artifactRefs: artifactReferences,
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
