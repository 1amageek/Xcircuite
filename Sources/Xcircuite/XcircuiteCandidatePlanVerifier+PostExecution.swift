import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import XcircuitePackage

extension XcircuiteCandidatePlanVerifier {
    func makePostExecutionPlanVerification(
        plan: XcircuiteCandidatePlan,
        candidatePlanRef: XcircuiteFileReference,
        actionDomainSnapshotRef: XcircuiteFileReference?,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        planningProblemValidationRef: XcircuiteFileReference?,
        planningProblem: XcircuiteCircuitPlanningProblem?,
        approvals: [XcircuiteApprovalRecord],
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) async throws -> XcircuitePlanVerification {
        let baseArtifactRefs = uniqueArtifactRefs(
            [candidatePlanRef] + [actionDomainSnapshotRef, planningProblemValidationRef].compactMap { $0 }
        )
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
        guard let executionRef = manifest.artifacts.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.planExecutionArtifactID
        }) else {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "plan-execution-missing",
                message: "Post-execution verification requires planning/plan-execution.json."
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
                verificationMode: "post-execution",
                planningProblem: planningProblem,
                planningProblemValidationRef: planningProblemValidationRef,
                actionDomainSnapshotRef: actionDomainSnapshotRef,
                stepResults: symbolicSummary.stepResults,
                gateResults: gateResults,
                goalCoverage: preExecutionGoalCoverage,
                artifactRefs: baseArtifactRefs,
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
        let execution = try packageStore.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: packageStore.url(forProjectRelativePath: executionRef.path, inProjectAt: projectRoot)
        )
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
        var artifactRefs = uniqueArtifactRefs(
            baseArtifactRefs + [executionRef]
                + execution.artifactRefs
                + [execution.designDiffRef].compactMap { $0 }
        )
        let gateEvaluation = try await makePostExecutionGateResults(
            plan: plan,
            execution: execution,
            stepResults: stepResults,
            riskReviews: riskReviews,
            artifactRefs: artifactRefs,
            manifest: manifest,
            projectRoot: projectRoot
        )
        artifactRefs = uniqueArtifactRefs(artifactRefs + gateEvaluation.artifactRefs)
        let requiredGateResults = gateEvaluation.gateResults.filter(\.required)
        let signoffEvidenceDiagnostics = missingPostExecutionSignoffEvidenceDiagnostics(
            requiredResults: requiredGateResults,
            artifactRefs: artifactRefs
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
            verificationMode: "post-execution",
            planningProblem: planningProblem,
            planningProblemValidationRef: planningProblemValidationRef,
            actionDomainSnapshotRef: actionDomainSnapshotRef,
            stepResults: stepResults,
            gateResults: gateEvaluation.gateResults,
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
            verificationMode: "post-execution",
            candidatePlanRef: candidatePlanRef,
            stepResults: stepResults,
            gateResults: gateEvaluation.gateResults,
            correctnessGateResults: correctnessGateResults,
            riskReviews: riskReviews,
            artifactRefs: artifactRefs,
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
            producedArtifactRefs: executed.artifactRefs
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
        artifactRefs: [XcircuiteFileReference],
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) async throws -> PostExecutionGateEvaluation {
        var gateResults: [XcircuitePlanVerificationGateResult] = []
        var producedArtifacts: [XcircuiteFileReference] = []
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
                    artifactRefs: artifactRefs,
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
                producedArtifacts.append(contentsOf: result.artifactRefs)
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
                producedArtifacts.append(contentsOf: result.artifactRefs)
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
                producedArtifacts.append(contentsOf: result.artifactRefs)
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
                producedArtifacts.append(contentsOf: result.artifactRefs)
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
        return PostExecutionGateEvaluation(gateResults: gateResults, artifactRefs: producedArtifacts)
    }
}
