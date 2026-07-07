import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import XcircuitePackage

extension XcircuiteCandidatePlanVerifier {
    func stepResult(
        for step: XcircuiteCandidatePlanStep,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        symbolicStateBefore: [String]
    ) -> XcircuitePlanVerificationStepResult {
        let symbolicEvaluation = symbolicEvaluation(
            for: step,
            actionDomainSnapshot: actionDomainSnapshot,
            symbolicStateBefore: symbolicStateBefore
        )
        let diagnostics = uniqueDiagnostics(
            step.blockers.map { diagnostic(for: $0, stepID: step.stepID) }
                + actionDomainDiagnostics(
                    for: step,
                    actionDomainSnapshot: actionDomainSnapshot,
                    symbolicStateBefore: symbolicStateBefore
                )
        )
        let status = diagnostics.isEmpty && step.readiness == "ready"
            ? "preflight-passed"
            : "blocked"
        return XcircuitePlanVerificationStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: status,
            gateIDs: step.verificationGates,
            symbolicEvaluation: symbolicEvaluation,
            diagnostics: diagnostics
        )
    }

    func stepResults(
        for plan: XcircuiteCandidatePlan,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?
    ) -> [XcircuitePlanVerificationStepResult] {
        symbolicVerificationSummary(
            for: plan,
            actionDomainSnapshot: actionDomainSnapshot,
            planningProblem: nil
        ).stepResults
    }

    func symbolicVerificationSummary(
        for plan: XcircuiteCandidatePlan,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        planningProblem: XcircuiteCircuitPlanningProblem?
    ) -> SymbolicVerificationSummary {
        let initialState = initialSymbolicState(for: plan, planningProblem: planningProblem)
        var symbolicState = initialState
        var results: [XcircuitePlanVerificationStepResult] = []
        for step in plan.steps.sorted(by: { $0.order < $1.order }) {
            let result = stepResult(
                for: step,
                actionDomainSnapshot: actionDomainSnapshot,
                symbolicStateBefore: symbolicState
            )
            if result.status == "preflight-passed", let evaluation = result.symbolicEvaluation {
                symbolicState = evaluation.stateAfter
            }
            results.append(result)
        }
        return SymbolicVerificationSummary(
            stepResults: results,
            initialSymbolicState: initialState,
            finalSymbolicState: symbolicState
        )
    }

    func postExecutionSymbolicVerificationSummary(
        for plan: XcircuiteCandidatePlan,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        planningProblem: XcircuiteCircuitPlanningProblem?,
        execution: XcircuiteCandidatePlanExecution
    ) -> SymbolicVerificationSummary {
        let initialState = initialSymbolicState(for: plan, planningProblem: planningProblem)
        var symbolicState = initialState
        var results: [XcircuitePlanVerificationStepResult] = []
        for step in plan.steps.sorted(by: { $0.order < $1.order }) {
            let result = postExecutionStepResult(
                for: step,
                execution: execution,
                actionDomainSnapshot: actionDomainSnapshot,
                symbolicStateBefore: symbolicState
            )
            if result.status == "executed" {
                var stateAfter = result.symbolicEvaluation?.stateAfter
                    ?? uniqueStrings(symbolicState + symbolicEffectAtoms(from: step.parameterHints))
                stateAfter.append(contentsOf: result.producedArtifactRefs.compactMap(\.artifactID).map {
                    "artifact:\($0)"
                })
                symbolicState = uniqueStrings(stateAfter)
            }
            results.append(result)
        }
        return SymbolicVerificationSummary(
            stepResults: results,
            initialSymbolicState: initialState,
            finalSymbolicState: symbolicState
        )
    }

    func symbolicEvaluation(
        for step: XcircuiteCandidatePlanStep,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        symbolicStateBefore: [String]
    ) -> XcircuiteSymbolicPlannerStepEvaluation? {
        guard let actionDomainSnapshot else { return nil }
        return symbolicPlannerContract.evaluation(
            for: step,
            actionDomainSnapshot: actionDomainSnapshot,
            symbolicStateBefore: symbolicStateBefore
        )
    }

    func initialSymbolicState(
        for plan: XcircuiteCandidatePlan,
        planningProblem: XcircuiteCircuitPlanningProblem?
    ) -> [String] {
        var atoms = [
            "ref:\(plan.sourceProblemRef.refID)",
            plan.sourceProblemRef.artifactID.map { "artifact:\($0)" },
        ].compactMap { $0 }
        if let planningProblem {
            atoms.append(contentsOf: (planningProblem.sourceRefs + planningProblem.initialStateRefs).flatMap { reference in
                var refAtoms = ["ref:\(reference.refID)"]
                if let artifactID = reference.artifactID {
                    refAtoms.append("artifact:\(artifactID)")
                }
                refAtoms.append(contentsOf: stringArrayValue(for: "symbolicStateAtoms", in: reference.metadata))
                refAtoms.append(contentsOf: stringArrayValue(for: "satisfiedPreconditions", in: reference.metadata))
                return refAtoms
            })
        }
        return uniqueStrings(atoms)
    }

    func goalCoverage(
        for objectives: [XcircuitePlanningObjective],
        finalSymbolicState: [String]
    ) -> [XcircuiteSymbolicPlannerGoalCoverage] {
        objectives.map { objective in
            let goalAtoms = symbolicGoalAtoms(for: objective)
            let satisfiedGoalAtoms = goalAtoms.filter { finalSymbolicState.contains($0) }
            let missingGoalAtoms = goalAtoms.filter { !finalSymbolicState.contains($0) }
            let status: String
            if goalAtoms.isEmpty {
                status = "not-declared"
            } else if missingGoalAtoms.isEmpty {
                status = "covered"
            } else {
                status = "missing"
            }
            return XcircuiteSymbolicPlannerGoalCoverage(
                objectiveID: objective.objectiveID,
                goalAtoms: goalAtoms,
                satisfiedGoalAtoms: satisfiedGoalAtoms,
                missingGoalAtoms: missingGoalAtoms,
                status: status
            )
        }
    }

    func goalCoverageStatus(
        from coverage: [XcircuiteSymbolicPlannerGoalCoverage]
    ) -> String {
        if coverage.contains(where: { $0.status == "missing" }) {
            return "missing"
        }
        if coverage.contains(where: { $0.status == "covered" }) {
            return "covered"
        }
        if coverage.isEmpty {
            return "not-evaluated"
        }
        return "not-declared"
    }

    func missingGoalAtomRefs(
        from coverage: [XcircuiteSymbolicPlannerGoalCoverage]
    ) -> [String] {
        uniqueStrings(
            coverage.flatMap { item in
                item.missingGoalAtoms.map { "\(item.objectiveID):\($0)" }
            }
        )
    }

    func goalCoverageDiagnostics(
        from coverage: [XcircuiteSymbolicPlannerGoalCoverage]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        coverage.flatMap { item in
            item.missingGoalAtoms.map { atom in
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "missing-goal-atom",
                    message: "missing-goal-atoms:\(item.objectiveID):\(atom)"
                )
            }
        }
    }

    func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        uniqueStrings(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    func symbolicEffectAtoms(from values: [String: XcircuiteJSONValue]) -> [String] {
        uniqueStrings(
            stringArrayValue(for: "symbolicEffects", in: values)
                + stringArrayValue(for: "satisfiesGoalAtoms", in: values)
                + stringArrayValue(for: "producedGoalAtoms", in: values)
        )
    }

    func stringArrayValue(
        for key: String,
        in values: [String: XcircuiteJSONValue]
    ) -> [String] {
        guard case .array(let items)? = values[key] else {
            return []
        }
        return items.compactMap { item in
            guard case .string(let value) = item else {
                return nil
            }
            return value
        }
    }

    func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    func actionDomainDiagnostics(
        for step: XcircuiteCandidatePlanStep,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        symbolicStateBefore: [String]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        guard let actionDomainSnapshot else { return [] }
        return symbolicPlannerContract.diagnostics(
            for: step,
            actionDomainSnapshot: actionDomainSnapshot,
            symbolicStateBefore: symbolicStateBefore
        )
    }

    func uniqueDiagnostics(
        _ diagnostics: [XcircuitePlanVerificationDiagnostic]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        var seen: Set<String> = []
        return diagnostics.filter { diagnostic in
            let key = [
                diagnostic.severity,
                diagnostic.code,
                diagnostic.message,
                diagnostic.stepID ?? "",
                diagnostic.gateID ?? "",
            ].joined(separator: "|")
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    func diagnostic(
        for blocker: String,
        stepID: String
    ) -> XcircuitePlanVerificationDiagnostic {
        if blocker.hasPrefix("operation-not-implemented:") {
            return XcircuitePlanVerificationDiagnostic(
                severity: "warning",
                code: "operation-not-implemented",
                message: blocker,
                stepID: stepID
            )
        }
        if blocker.hasPrefix("missing-input-refs:") {
            return XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "missing-input-refs",
                message: blocker,
                stepID: stepID
            )
        }
        return XcircuitePlanVerificationDiagnostic(
            severity: "error",
            code: "step-blocked",
            message: blocker,
            stepID: stepID
        )
    }

    func planDiagnostics(
        for plan: XcircuiteCandidatePlan,
        stepResults: [XcircuitePlanVerificationStepResult]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        var diagnostics: [XcircuitePlanVerificationDiagnostic] = []
        diagnostics.append(contentsOf: plan.unresolvedObjectives.map {
            XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "unresolved-objective",
                message: "No candidate step resolves objective \($0)."
            )
        })
        diagnostics.append(contentsOf: stepResults.flatMap(\.diagnostics))
        return diagnostics
    }
}
