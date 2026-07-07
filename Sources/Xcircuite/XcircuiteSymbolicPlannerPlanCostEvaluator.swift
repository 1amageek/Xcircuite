public struct XcircuiteSymbolicPlannerPlanCostEvaluator: Sendable {
    public init() {}

    public func evaluate(
        candidatePlan: XcircuiteCandidatePlan,
        pddlExport: XcircuiteSymbolicPlannerPDDLExport? = nil
    ) -> XcircuiteSymbolicPlannerPlanCostEvaluation {
        let costByActionID = actionCosts(from: pddlExport)
        let stepCosts = candidatePlan.steps.map { step in
            XcircuiteSymbolicPlannerPlanCostStep(
                stepID: step.stepID,
                actionID: step.actionID,
                order: step.order,
                cost: costByActionID[step.actionID] ?? 1
            )
        }
        let evaluatedCost = stepCosts.reduce(0) { $0 + $1.cost }
        return XcircuiteSymbolicPlannerPlanCostEvaluation(
            strategy: pddlExport == nil ? "unit-action-cost" : "pddl-action-cost",
            planID: candidatePlan.planID,
            planLength: candidatePlan.steps.count,
            evaluatedCost: evaluatedCost,
            evaluatedCostUnit: "planner action cost",
            stepCosts: stepCosts
        )
    }

    private func actionCosts(
        from pddlExport: XcircuiteSymbolicPlannerPDDLExport?
    ) -> [String: Double] {
        guard let pddlExport else {
            return [:]
        }
        var costs: [String: Double] = [:]
        for mapping in pddlExport.actionMappings where mapping.included {
            guard let actionCost = mapping.actionCost,
                  actionCost.isFinite,
                  actionCost > 0 else {
                continue
            }
            costs[mapping.actionID] = actionCost
        }
        return costs
    }
}
