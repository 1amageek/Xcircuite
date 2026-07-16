import Foundation
import DesignFlowKernel

extension XcircuiteCandidatePlanGenerator {
    func initialSymbolicState(for problem: XcircuiteCircuitPlanningProblem) -> [String] {
        unique(
            (problem.sourceRefs + problem.initialStateRefs).flatMap { reference in
                var atoms = ["ref:\(reference.refID)"]
                if let artifactID = reference.artifactID {
                    atoms.append("artifact:\(artifactID)")
                }
                atoms.append(contentsOf: symbolicStateAtoms(from: reference.metadata))
                return atoms
            }
        )
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
        return "not-declared"
    }

    func missingGoalAtomRefs(
        from coverage: [XcircuiteSymbolicPlannerGoalCoverage]
    ) -> [String] {
        unique(
            coverage.flatMap { item in
                item.missingGoalAtoms.map { "\(item.objectiveID):\($0)" }
            }
        )
    }

    func goalCoverageBlockers(
        from coverage: [XcircuiteSymbolicPlannerGoalCoverage]
    ) -> [String] {
        coverage.compactMap { item in
            guard !item.missingGoalAtoms.isEmpty else {
                return nil
            }
            return "missing-goal-atoms:\(item.objectiveID):\(item.missingGoalAtoms.joined(separator: ","))"
        }
    }

    func symbolicStateAtoms(from hints: [String: PlanningParameterValue]) -> [String] {
        unique(
            stringArrayValue(for: "symbolicStateAtoms", in: hints)
                + stringArrayValue(for: "satisfiedPreconditions", in: hints)
        )
    }

    func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        unique(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    func candidateEffectAtoms(
        for action: XcircuitePlanningCandidateAction,
        operation: XcircuiteActionDomainOperation?
    ) -> [String] {
        unique(
            (operation?.effects ?? [])
                + (operation?.producedArtifacts.map { "artifact:\($0)" } ?? [])
                + stringArrayValue(for: "symbolicEffects", in: action.parameterHints)
                + stringArrayValue(for: "satisfiesGoalAtoms", in: action.parameterHints)
                + stringArrayValue(for: "producedGoalAtoms", in: action.parameterHints)
        )
    }

    func stringArrayValue(
        for key: String,
        in values: [String: PlanningParameterValue]
    ) -> [String] {
        guard case .textList(let items)? = values[key] else {
            return []
        }
        return items
    }

    func weightedPenalty(
        for termID: String,
        in costModel: XcircuitePlanningCostModel,
        defaultValue: Int
    ) -> Int {
        guard let term = costModel.terms.first(where: { $0.termID == termID }) else {
            return defaultValue
        }
        guard term.weight.isFinite, term.weight >= 0 else {
            return defaultValue
        }
        let rounded = Int(term.weight.rounded(.toNearestOrAwayFromZero))
        if term.direction == "maximize" {
            return -rounded
        }
        return rounded
    }

    func weightedReward(
        for termID: String,
        in costModel: XcircuitePlanningCostModel,
        defaultValue: Int
    ) -> Int {
        guard let term = costModel.terms.first(where: { $0.termID == termID }) else {
            return defaultValue
        }
        guard term.weight.isFinite, term.weight >= 0 else {
            return defaultValue
        }
        let rounded = Int(term.weight.rounded(.toNearestOrAwayFromZero))
        if term.direction == "minimize" {
            return -rounded
        }
        return rounded
    }

    func missingInputRefs(
        for action: XcircuitePlanningCandidateAction,
        availableRefs: [String: XcircuitePlanningReference]
    ) -> [String] {
        action.requiredInputRefs.filter { refID in
            guard let reference = availableRefs[refID] else {
                return true
            }
            return reference.path == nil && reference.artifactID == nil
        }
    }

    func actionBlockers(
        for action: XcircuitePlanningCandidateAction,
        domain: XcircuiteActionDomain?,
        operation: XcircuiteActionDomainOperation?,
        missingRefs: [String],
        actionDomainSnapshotLoaded: Bool
    ) -> [String] {
        var blockers: [String] = []
        if actionDomainSnapshotLoaded && domain == nil {
            blockers.append("unsupported-action-domain:\(action.domainID)")
        }
        if domain != nil && operation == nil {
            blockers.append("unsupported-operation:\(action.domainID)/\(action.operationID)")
        }
        if let operation, operation.maturity != action.maturity {
            blockers.append("action-domain-maturity-mismatch:\(action.domainID)/\(action.operationID)")
        }
        let effectiveMaturity = operation?.maturity ?? action.maturity
        if effectiveMaturity != "implemented" {
            blockers.append("operation-not-implemented:\(action.domainID)/\(action.operationID)")
        }
        if !missingRefs.isEmpty {
            blockers.append("missing-input-refs:\(missingRefs.joined(separator: ","))")
        }
        return blockers
    }

    func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    func isHardBlocker(_ blocker: String) -> Bool {
        blocker.contains(":missing-input-refs:")
            || blocker.contains(":unsupported-action-domain:")
            || blocker.contains(":unsupported-operation:")
            || blocker.contains(":action-domain-maturity-mismatch:")
            || blocker.contains("missing-goal-atoms:")
    }
}
