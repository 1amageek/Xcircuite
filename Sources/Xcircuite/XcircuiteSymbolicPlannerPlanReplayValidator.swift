public struct XcircuiteSymbolicPlannerPlanReplayValidator: Sendable {
    public init() {}

    public func validate(
        candidatePlan: XcircuiteCandidatePlan,
        pddlExport: XcircuiteSymbolicPlannerPDDLExport
    ) -> XcircuiteSymbolicPlannerPlanReplayValidation {
        let initialAtoms = pddlExport.atomMappings
            .filter { $0.roles.contains("initial") }
            .map(\.atom)
            .sorted()
        let goalAtoms = pddlExport.atomMappings
            .filter { $0.roles.contains("goal") }
            .map(\.atom)
            .sorted()
        var mappingByActionID: [String: XcircuiteSymbolicPlannerPDDLActionMapping] = [:]
        for mapping in pddlExport.actionMappings where mappingByActionID[mapping.actionID] == nil {
            mappingByActionID[mapping.actionID] = mapping
        }

        var currentAtoms = Set(initialAtoms)
        var steps: [XcircuiteSymbolicPlannerPlanReplayStepValidation] = []
        var diagnostics: [XcircuiteSymbolicPlannerPlanReplayDiagnostic] = []
        var evaluatedCost = 0.0

        if candidatePlan.steps.isEmpty {
            diagnostics.append(
                XcircuiteSymbolicPlannerPlanReplayDiagnostic(
                    severity: "error",
                    code: "empty-plan",
                    message: "Imported symbolic planner candidate plan does not contain any steps."
                )
            )
        }

        for step in candidatePlan.steps.sorted(by: { $0.order < $1.order }) {
            let stateBefore = currentAtoms.sorted()
            guard let mapping = mappingByActionID[step.actionID] else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanReplayDiagnostic(
                        severity: "error",
                        code: "action-mapping-missing",
                        message: "Candidate plan step \(step.stepID) references action \(step.actionID), but the PDDL export does not contain an action mapping for it.",
                        stepID: step.stepID,
                        actionID: step.actionID
                    )
                )
                steps.append(
                    XcircuiteSymbolicPlannerPlanReplayStepValidation(
                        stepID: step.stepID,
                        order: step.order,
                        actionID: step.actionID,
                        pddlAction: nil,
                        status: "failed",
                        preconditionAtoms: [],
                        missingPreconditionAtoms: [],
                        effectAtoms: [],
                        stateBefore: stateBefore,
                        stateAfter: stateBefore,
                        actionCost: 0
                    )
                )
                continue
            }
            guard mapping.included else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanReplayDiagnostic(
                        severity: "error",
                        code: "excluded-action-mapping",
                        message: "Candidate plan step \(step.stepID) maps to excluded PDDL action \(mapping.pddlAction).",
                        stepID: step.stepID,
                        actionID: step.actionID,
                        pddlAction: mapping.pddlAction
                    )
                )
                steps.append(
                    XcircuiteSymbolicPlannerPlanReplayStepValidation(
                        stepID: step.stepID,
                        order: step.order,
                        actionID: step.actionID,
                        pddlAction: mapping.pddlAction,
                        status: "failed",
                        preconditionAtoms: mapping.preconditionAtoms.sorted(),
                        missingPreconditionAtoms: mapping.preconditionAtoms.sorted(),
                        effectAtoms: mapping.effectAtoms.sorted(),
                        stateBefore: stateBefore,
                        stateAfter: stateBefore,
                        actionCost: 0
                    )
                )
                continue
            }

            let missingPreconditions = mapping.preconditionAtoms
                .filter { !currentAtoms.contains($0) }
                .sorted()
            let actionCost = normalizedActionCost(mapping.actionCost)
            evaluatedCost += actionCost
            if missingPreconditions.isEmpty {
                currentAtoms.formUnion(mapping.effectAtoms)
            } else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanReplayDiagnostic(
                        severity: "error",
                        code: "preconditions-unsatisfied",
                        message: "Candidate plan step \(step.stepID) cannot be applied because required PDDL preconditions are missing.",
                        stepID: step.stepID,
                        actionID: step.actionID,
                        pddlAction: mapping.pddlAction,
                        atoms: missingPreconditions
                    )
                )
            }

            steps.append(
                XcircuiteSymbolicPlannerPlanReplayStepValidation(
                    stepID: step.stepID,
                    order: step.order,
                    actionID: step.actionID,
                    pddlAction: mapping.pddlAction,
                    status: missingPreconditions.isEmpty ? "applied" : "failed",
                    preconditionAtoms: mapping.preconditionAtoms.sorted(),
                    missingPreconditionAtoms: missingPreconditions,
                    effectAtoms: mapping.effectAtoms.sorted(),
                    stateBefore: stateBefore,
                    stateAfter: currentAtoms.sorted(),
                    actionCost: actionCost
                )
            )
        }

        let missingGoalAtoms = goalAtoms.filter { !currentAtoms.contains($0) }
        if !missingGoalAtoms.isEmpty {
            diagnostics.append(
                XcircuiteSymbolicPlannerPlanReplayDiagnostic(
                    severity: "error",
                    code: "goals-unsatisfied",
                    message: "Replayed symbolic planner plan does not satisfy all PDDL goal atoms.",
                    atoms: missingGoalAtoms
                )
            )
        }

        let status = diagnostics.contains(where: { $0.severity == "error" }) ? "failed" : "validated"
        return XcircuiteSymbolicPlannerPlanReplayValidation(
            status: status,
            runID: candidatePlan.runID,
            problemID: candidatePlan.problemID,
            planID: candidatePlan.planID,
            validationStrategy: "pddl-additive-precondition-effect-replay",
            initialAtoms: initialAtoms,
            goalAtoms: goalAtoms,
            finalAtoms: currentAtoms.sorted(),
            missingGoalAtoms: missingGoalAtoms,
            evaluatedCost: evaluatedCost,
            evaluatedCostUnit: "planner action cost",
            steps: steps,
            diagnostics: diagnostics
        )
    }

    private func normalizedActionCost(_ cost: Double?) -> Double {
        guard let cost,
              cost.isFinite,
              cost > 0 else {
            return 1
        }
        return cost
    }
}
