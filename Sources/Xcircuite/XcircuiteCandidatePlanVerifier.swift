import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import XcircuitePackage

public struct XcircuiteCandidatePlanVerifier: Sendable {
    let packageStore: XcircuitePackageStore
    let artifactStore: XcircuitePlanningArtifactStore
    let artifactBuilder: StageArtifactReferenceBuilder
    let layoutDocumentSerializer: LayoutDocumentSerializer
    let symbolicPlannerContract: XcircuiteSymbolicPlannerContract
    let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
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
        let plan = try packageStore.readJSON(
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
        let approvals = try packageStore.loadApprovals(
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
            planVerificationArtifact: verificationRef,
            rejectedPlansArtifact: rejectedPlansRef,
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
        let artifactRefs = uniqueArtifactRefs(
            [candidatePlanRef] + [actionDomainSnapshotRef, planningProblemValidationRef].compactMap { $0 }
        )
        let gateResults = makeGateResults(
            plan: plan,
            stepResults: stepResults,
            riskReviews: riskReviews,
            artifactRefs: artifactRefs,
            projectRoot: projectRoot
        )
        let diagnostics = planDiagnostics(for: plan, stepResults: stepResults)
            + riskReviewer.blockingDiagnostics(from: riskReviews)
            + goalCoverageDiagnostics(from: goalCoverage)
            + gateResults.flatMap(\.diagnostics)
        let nextActions = makeNextActions(
            plan: plan,
            stepResults: stepResults,
            gateResults: gateResults,
            riskReviews: riskReviews,
            goalCoverage: goalCoverage
        )
        let accepted = stepResults.allSatisfy { $0.status == "preflight-passed" }
            && gateResults.filter(\.required).allSatisfy { $0.status == "passed" }
            && !riskReviewer.blocksExecution(riskReviews)
            && !goalCoverage.contains(where: { $0.status == "missing" })
            && plan.unresolvedObjectives.isEmpty
        let correctnessGateResults = makeCorrectnessGateResults(
            plan: plan,
            verificationMode: verificationMode,
            planningProblem: planningProblem,
            planningProblemValidationRef: planningProblemValidationRef,
            actionDomainSnapshotRef: actionDomainSnapshotRef,
            stepResults: stepResults,
            gateResults: gateResults,
            goalCoverage: goalCoverage,
            artifactRefs: artifactRefs,
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
            artifactRefs: artifactRefs,
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
