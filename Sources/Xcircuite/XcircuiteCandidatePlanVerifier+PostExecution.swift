import Foundation
import CircuiteFoundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func makePostExecutionPlanVerification(
        plan: XcircuiteCandidatePlan,
        candidatePlanRef: ArtifactReference,
        actionDomainSnapshotRef: ArtifactReference?,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        planningProblemValidationRef: ArtifactReference?,
        planningProblem: XcircuiteCircuitPlanningProblem?,
        approvals: [FlowApprovalRecord],
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> XcircuitePlanVerification {
        let baseArtifactRefs = uniqueArtifactReferences([candidatePlanRef] + [actionDomainSnapshotRef, planningProblemValidationRef].compactMap { $0 })
        let planningProblemValidationArtifact = planningProblemValidationRef
        let actionDomainSnapshotArtifact = actionDomainSnapshotRef
        let symbolicSummary = symbolicVerificationSummary(
            for: plan,
            actionDomainSnapshot: actionDomainSnapshot,
            planningProblem: planningProblem
        )
        let preExecutionGoalCoverage = goalCoverage(
            for: planningProblem?.objectives ?? [],
            finalSymbolicState: symbolicSummary.finalSymbolicState
        )
        let preExecutionMissingGoalAtoms = missingGoalAtomRefs(from: preExecutionGoalCoverage)
        let riskReviewer = XcircuiteCandidatePlanRiskReviewer()
        let riskReviews = riskReviewer.riskReviews(for: plan, approvals: approvals)
        guard let executionInput = try await matchingPlanExecution(
            runID: plan.runID,
            candidatePlanRef: candidatePlanRef,
            manifest: manifest
        ) else {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "plan-execution-missing",
                message: "Post-execution verification requires an action-bound planning/plan-execution/<sha256>.json artifact."
            )
            let gateResults = postExecutionGateResultsWithoutExecution(
                plan: plan,
                diagnostic: diagnostic,
                riskReviews: riskReviews,
                actionDomainSnapshot: actionDomainSnapshot
            )
            let diagnostics = [diagnostic]
                + riskReviewer.blockingDiagnostics(from: riskReviews)
                + goalCoverageDiagnostics(from: preExecutionGoalCoverage)
                + gateResults.flatMap(\.diagnostics)
            let nextActions = unique(["execute-candidate-plan"] + riskReviewer.nextActions(from: riskReviews))
            let correctnessGateResults = makeCorrectnessGateResults(
                plan: plan,
                candidatePlanArtifact: candidatePlanRef,
                verificationMode: "post-execution",
                planningProblem: planningProblem,
                planningProblemValidationArtifact: planningProblemValidationArtifact,
                actionDomainSnapshotArtifact: actionDomainSnapshotArtifact,
                stepResults: symbolicSummary.stepResults,
                gateResults: gateResults,
                goalCoverage: preExecutionGoalCoverage,
                artifactReferences: baseArtifactRefs,
                diagnostics: diagnostics,
                accepted: false,
                nextActions: nextActions
            )
            return XcircuitePlanVerification(
                problemID: plan.problemID,
                planID: plan.planID,
                runID: plan.runID,
                verificationMode: "post-execution",
                candidatePlanRef: candidatePlanRef,
                stepResults: symbolicSummary.stepResults,
                gateResults: gateResults,
                correctnessGateResults: correctnessGateResults,
                riskReviews: riskReviews,
                artifactRefs: baseArtifactRefs,
                initialSymbolicState: symbolicSummary.initialSymbolicState,
                finalSymbolicState: symbolicSummary.finalSymbolicState,
                goalCoverageStatus: goalCoverageStatus(from: preExecutionGoalCoverage),
                goalCoverage: preExecutionGoalCoverage,
                missingGoalAtoms: preExecutionMissingGoalAtoms,
                diagnostics: diagnostics,
                accepted: false,
                nextActions: nextActions
            )
        }
        let executionRef = executionInput.reference
        let execution = executionInput.execution
        let postExecutionSymbolicSummary = postExecutionSymbolicVerificationSummary(
            for: plan,
            actionDomainSnapshot: actionDomainSnapshot,
            planningProblem: planningProblem,
            execution: execution
        )
        let stepResults = postExecutionSymbolicSummary.stepResults
        let goalCoverage = goalCoverage(
            for: planningProblem?.objectives ?? [],
            finalSymbolicState: postExecutionSymbolicSummary.finalSymbolicState
        )
        let missingGoalAtoms = missingGoalAtomRefs(from: goalCoverage)
        let executionArtifactReferences = [executionRef]
        let designDiffArtifactReferences = [execution.designDiffRef].compactMap { $0 }
        var artifactReferences = uniqueArtifactReferences(
            baseArtifactRefs
                + executionArtifactReferences
                + execution.artifactReferences
                + designDiffArtifactReferences
        )
        let gateEvaluation = try await makePostExecutionGateResults(
            plan: plan,
            execution: execution,
            stepResults: stepResults,
            riskReviews: riskReviews,
            artifactReferences: artifactReferences,
            manifest: manifest,
            projectRoot: projectRoot
        )
        artifactReferences = uniqueArtifactReferences(
            artifactReferences + gateEvaluation.artifactReferences
        )
        let requiredGateResults = gateEvaluation.gateResults.filter(\.required)
        let signoffEvidenceDiagnostics = missingPostExecutionSignoffEvidenceDiagnostics(
            requiredResults: requiredGateResults,
            artifactReferences: artifactReferences
        )
        let diagnostics = planDiagnostics(for: plan, stepResults: stepResults)
            + riskReviewer.blockingDiagnostics(from: riskReviews)
            + goalCoverageDiagnostics(from: goalCoverage)
            + gateEvaluation.gateResults.flatMap(\.diagnostics)
            + signoffEvidenceDiagnostics
        let nextActions = unique(
            makeNextActions(
                plan: plan,
                stepResults: stepResults,
                gateResults: gateEvaluation.gateResults,
                riskReviews: riskReviews,
                goalCoverage: goalCoverage
            )
                + signoffEvidenceDiagnostics.flatMap { self.nextActions(for: $0) }
        )
        let accepted = stepResults.allSatisfy { $0.status == "executed" }
            && requiredGateResults.allSatisfy { $0.status == "passed" }
            && signoffEvidenceDiagnostics.isEmpty
            && !riskReviewer.blocksExecution(riskReviews)
            && !goalCoverage.contains(where: { $0.status == "missing" })
            && plan.unresolvedObjectives.isEmpty
        let correctnessGateResults = makeCorrectnessGateResults(
            plan: plan,
            candidatePlanArtifact: candidatePlanRef,
            verificationMode: "post-execution",
            planningProblem: planningProblem,
            planningProblemValidationArtifact: planningProblemValidationArtifact,
            actionDomainSnapshotArtifact: actionDomainSnapshotArtifact,
            stepResults: stepResults,
            gateResults: gateEvaluation.gateResults,
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
            verificationMode: "post-execution",
            candidatePlanRef: candidatePlanRef,
            stepResults: stepResults,
            gateResults: gateEvaluation.gateResults,
            correctnessGateResults: correctnessGateResults,
            riskReviews: riskReviews,
            artifactRefs: artifactReferences,
            initialSymbolicState: postExecutionSymbolicSummary.initialSymbolicState,
            finalSymbolicState: postExecutionSymbolicSummary.finalSymbolicState,
            goalCoverageStatus: goalCoverageStatus(from: goalCoverage),
            goalCoverage: goalCoverage,
            missingGoalAtoms: missingGoalAtoms,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: nextActions
        )
    }

    private func matchingPlanExecution(
        runID: String,
        candidatePlanRef: ArtifactReference,
        manifest: FlowRunManifest
    ) async throws -> (reference: ArtifactReference, execution: XcircuiteCandidatePlanExecution)? {
        let candidates = manifest.artifacts.filter {
            $0.artifactID == XcircuitePlanningArtifactStore.planExecutionArtifactID
        }
        var matches: [(ArtifactReference, XcircuiteCandidatePlanExecution)] = []
        for reference in candidates {
            let execution: XcircuiteCandidatePlanExecution = try await decodeRetainedArtifact(
                reference,
                as: XcircuiteCandidatePlanExecution.self
            )
            if execution.candidatePlanRef == candidatePlanRef {
                matches.append((reference, execution))
            }
        }
        guard matches.count > 1 else {
            return matches.first
        }
        let matchesByReference = Dictionary(uniqueKeysWithValues: matches.map { ($0.0, $0.1) })
        let actions = try await workspaceStore.loadRunActions(runID: runID)
        for action in actions.reversed() where action.actionKind == "planning.execute-candidate-plan" {
            for output in action.outputs {
                if let execution = matchesByReference[output] {
                    return (output, execution)
                }
            }
        }
        throw XcircuiteCandidatePlanVerificationError.invalidArtifactPayload(
            path: candidatePlanRef.path,
            reason: "Multiple plan executions reference the same candidate plan without an ordered action binding."
        )
    }

    func postExecutionStepResult(
        for step: XcircuiteCandidatePlanStep,
        execution: XcircuiteCandidatePlanExecution,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot? = nil,
        symbolicStateBefore: [String] = []
    ) -> XcircuitePlanVerificationStepResult {
        guard let executed = execution.stepResults.first(where: { $0.stepID == step.stepID }) else {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "step-execution-missing",
                message: "Candidate plan step \(step.stepID) has no execution result.",
                stepID: step.stepID
            )
            return XcircuitePlanVerificationStepResult(
                stepID: step.stepID,
                order: step.order,
                actionID: step.actionID,
                domainID: step.domainID,
                operationID: step.operationID,
                status: "blocked",
                gateIDs: step.verificationGates,
                diagnostics: [diagnostic]
            )
        }
        let symbolicEvaluation = symbolicEvaluation(
            for: step,
            actionDomainSnapshot: actionDomainSnapshot,
            symbolicStateBefore: symbolicStateBefore
        )
        return XcircuitePlanVerificationStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: executed.status,
            gateIDs: step.verificationGates,
            symbolicEvaluation: symbolicEvaluation,
            diagnostics: executed.diagnostics,
            producedArtifactRefs: executed.artifactReferences
        )
    }

    func postExecutionGateResultsWithoutExecution(
        plan: XcircuiteCandidatePlan,
        diagnostic: XcircuitePlanVerificationDiagnostic,
        riskReviews: [XcircuitePlanRiskReview],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?
    ) -> [XcircuitePlanVerificationGateResult] {
        let stepResults = stepResults(for: plan, actionDomainSnapshot: actionDomainSnapshot)
        return gateSpecifications(plan: plan, stepResults: stepResults, riskReviews: riskReviews).map { gate in
            XcircuitePlanVerificationGateResult(
                gateID: gate.gateID,
                required: gate.required,
                status: "blocked",
                sourceStepIDs: stepResults.filter { $0.gateIDs.contains(gate.gateID) }.map(\.stepID),
                diagnostics: [diagnostic]
            )
        }
    }

    func makePostExecutionGateResults(
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        stepResults: [XcircuitePlanVerificationStepResult],
        riskReviews: [XcircuitePlanRiskReview],
        artifactReferences: [ArtifactReference],
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> PostExecutionGateEvaluation {
        var gateResults: [XcircuitePlanVerificationGateResult] = []
        var producedArtifactReferences: [ArtifactReference] = []
        for gate in gateSpecifications(plan: plan, stepResults: stepResults, riskReviews: riskReviews) {
            let sourceStepIDs = stepResults.filter { $0.gateIDs.contains(gate.gateID) }.map(\.stepID)
            if stepResults.contains(where: { $0.status != "executed" && $0.gateIDs.contains(gate.gateID) }) {
                gateResults.append(XcircuitePlanVerificationGateResult(
                    gateID: gate.gateID,
                    required: gate.required,
                    status: "blocked",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "error",
                            code: "gate-blocked-by-step-execution",
                            message: "Gate \(gate.gateID) cannot run because at least one source step did not execute.",
                            gateID: gate.gateID
                        ),
                    ]
                ))
                continue
            }
            switch gate.gateID {
            case "artifact-integrity", "schema-validation", "precondition-validation":
                gateResults.append(artifactIntegrityGateResult(
                    gateID: gate.gateID,
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    artifactRefs: artifactReferences,
                    projectRoot: projectRoot
                ))
            case "native-drc":
                let result = try await nativeDRCGateResult(
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    plan: plan,
                    execution: execution,
                    projectRoot: projectRoot
                )
                gateResults.append(result.gateResult)
                producedArtifactReferences.append(contentsOf: result.artifactReferences)
            case "native-lvs":
                let result = try await nativeLVSGateResult(
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    plan: plan,
                    execution: execution,
                    manifest: manifest,
                    projectRoot: projectRoot
                )
                gateResults.append(result.gateResult)
                producedArtifactReferences.append(contentsOf: result.artifactReferences)
            case "pex-summary-gate":
                let result = try await pexSummaryGateResult(
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    plan: plan,
                    execution: execution,
                    manifest: manifest,
                    projectRoot: projectRoot
                )
                gateResults.append(result.gateResult)
                producedArtifactReferences.append(contentsOf: result.artifactReferences)
            case "simulation-metric-gate":
                let result = try await simulationMetricGateResult(
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    plan: plan,
                    execution: execution,
                    manifest: manifest,
                    projectRoot: projectRoot
                )
                gateResults.append(result.gateResult)
                producedArtifactReferences.append(contentsOf: result.artifactReferences)
            case "approval-gate":
                gateResults.append(approvalGateResult(
                    gateID: gate.gateID,
                    required: gate.required,
                    sourceStepIDs: sourceStepIDs,
                    riskReviews: riskReviews
                ))
            default:
                gateResults.append(XcircuitePlanVerificationGateResult(
                    gateID: gate.gateID,
                    required: gate.required,
                    status: "pending",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "warning",
                            code: "gate-execution-required",
                            message: "Gate \(gate.gateID) requires a stage executor result before plan acceptance.",
                            gateID: gate.gateID
                        ),
                    ]
                ))
            }
        }
        return PostExecutionGateEvaluation(
            gateResults: gateResults,
            artifactReferences: producedArtifactReferences
        )
    }

}
