import Foundation
import DesignFlowKernel

public struct XcircuiteRepairPlanFormulationCompiler: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
    }

    public func compile(
        request: XcircuiteRepairPlanFormulationCompilationRequest,
        projectRoot: URL
    ) throws -> XcircuiteRepairPlanFormulationCompilationResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let formulation = try loadFormulation(request: request, projectRoot: projectRoot)
        try validate(formulation: formulation, expectedRunID: request.runID)
        let formulationArtifact = try artifactStore.persistRepairPlanFormulation(
            formulation,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problemID = try resolvedProblemID(
            requestProblemID: request.problemID,
            formulationID: formulation.formulationID,
            runID: request.runID
        )
        let problem = makePlanningProblem(
            formulation: formulation,
            problemID: problemID,
            formulationArtifact: formulationArtifact
        )
        let problemArtifact = try artifactStore.persistPlanningProblem(
            problem,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteRepairPlanFormulationCompilationResult(
            status: "compiled",
            runID: request.runID,
            formulationID: formulation.formulationID,
            problemID: problemID,
            formulationArtifact: formulationArtifact,
            problemArtifact: problemArtifact,
            diagnosticCodes: diagnostics(for: formulation)
        )
    }

    private func loadFormulation(
        request: XcircuiteRepairPlanFormulationCompilationRequest,
        projectRoot: URL
    ) throws -> XcircuiteRepairPlanFormulation {
        if let formulation = request.formulation {
            return formulation
        }
        guard let formulationPath = request.formulationPath else {
            throw XcircuiteRepairPlanFormulationCompilationError.missingFormulation
        }
        let formulationURL = try workspaceStore.url(
            forProjectRelativePath: formulationPath,
            inProjectAt: projectRoot
        )
        return try workspaceStore.readJSON(XcircuiteRepairPlanFormulation.self, from: formulationURL)
    }

    private func validate(
        formulation: XcircuiteRepairPlanFormulation,
        expectedRunID: String
    ) throws {
        guard formulation.schemaVersion == 1 else {
            throw XcircuiteRepairPlanFormulationCompilationError.unsupportedSchemaVersion(
                formulation.schemaVersion
            )
        }
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(formulation.formulationID, kind: .artifactID)
        try validator.validate(formulation.intentID, kind: .artifactID)
        try validator.validate(formulation.runID, kind: .runID)
        guard formulation.runID == expectedRunID else {
            throw XcircuiteRepairPlanFormulationCompilationError.runMismatch(
                expected: expectedRunID,
                actual: formulation.runID
            )
        }
        guard !formulation.goals.isEmpty else {
            throw XcircuiteRepairPlanFormulationCompilationError.emptyGoals
        }
        guard !formulation.actions.isEmpty else {
            throw XcircuiteRepairPlanFormulationCompilationError.emptyActions
        }
        let sourceRefIDList = formulation.sourceRefs.map(\.refID) + formulation.initialStateRefs.map(\.refID)
        try validateUniqueArtifactIDs(
            sourceRefIDList,
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateReferenceID
        )
        try validateUniqueArtifactIDs(
            formulation.assumptions.map(\.assumptionID),
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateAssumptionID
        )
        try validateUniqueArtifactIDs(
            formulation.riskClassifications.map(\.riskID),
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateRiskID
        )
        let goalIDList = formulation.goals.map(\.goalID)
        try validateUniqueArtifactIDs(
            goalIDList,
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateGoalID
        )
        try validateUniqueArtifactIDs(
            formulation.constraints.map(\.constraintID),
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateConstraintID
        )
        try validateUniqueArtifactIDs(
            formulation.actionDomainRefs,
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateActionDomainRef
        )
        try validateUniqueArtifactIDs(
            formulation.verificationGates.map(\.gateID),
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateVerificationGateID
        )
        if let costModel = formulation.costModel {
            try validateUniqueArtifactIDs(
                costModel.terms.map(\.termID),
                validator: validator,
                duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateCostTermID
            )
        }
        let actionIDList = formulation.actions.map(\.actionID)
        try validateUniqueArtifactIDs(
            actionIDList,
            validator: validator,
            duplicateError: XcircuiteRepairPlanFormulationCompilationError.duplicateActionID
        )
        let sourceRefIDs = Set(sourceRefIDList)
        let goalIDs = Set(goalIDList)
        for goal in formulation.goals {
            try validateUniqueArtifactIDs(
                goal.sourceRefIDs,
                validator: validator,
                duplicateError: { duplicateRefID in
                    XcircuiteRepairPlanFormulationCompilationError.duplicateGoalSourceReference(
                        goalID: goal.goalID,
                        refID: duplicateRefID
                    )
                }
            )
            for refID in goal.sourceRefIDs where !sourceRefIDs.contains(refID) {
                throw XcircuiteRepairPlanFormulationCompilationError.unknownSourceReference(
                    goalID: goal.goalID,
                    refID: refID
                )
            }
        }
        for action in formulation.actions {
            try validator.validate(action.domainID, kind: .artifactID)
            try validator.validate(action.operationID, kind: .artifactID)
            try validateUniqueArtifactIDs(
                action.sourceGoalIDs,
                validator: validator,
                duplicateError: { duplicateGoalID in
                    XcircuiteRepairPlanFormulationCompilationError.duplicateActionGoalReference(
                        actionID: action.actionID,
                        goalID: duplicateGoalID
                    )
                }
            )
            try validateUniqueArtifactIDs(
                action.requiredInputRefs,
                validator: validator,
                duplicateError: { duplicateRefID in
                    XcircuiteRepairPlanFormulationCompilationError.duplicateActionInputReference(
                        actionID: action.actionID,
                        refID: duplicateRefID
                    )
                }
            )
            try validateUniqueArtifactIDs(
                action.verificationGates,
                validator: validator,
                duplicateError: { duplicateGateID in
                    XcircuiteRepairPlanFormulationCompilationError.duplicateActionVerificationGateID(
                        actionID: action.actionID,
                        gateID: duplicateGateID
                    )
                }
            )
            for goalID in action.sourceGoalIDs where !goalIDs.contains(goalID) {
                throw XcircuiteRepairPlanFormulationCompilationError.unknownGoalReference(
                    actionID: action.actionID,
                    goalID: goalID
                )
            }
            for refID in action.requiredInputRefs where !sourceRefIDs.contains(refID) {
                throw XcircuiteRepairPlanFormulationCompilationError.unknownInputReference(
                    actionID: action.actionID,
                    refID: refID
                )
            }
        }
    }

    private func resolvedProblemID(
        requestProblemID: String?,
        formulationID: String,
        runID: String
    ) throws -> String {
        let problemID = requestProblemID ?? "\(runID)-\(formulationID)-problem"
        try XcircuiteIdentifierValidator().validate(problemID, kind: .artifactID)
        return problemID
    }

    private func makePlanningProblem(
        formulation: XcircuiteRepairPlanFormulation,
        problemID: String,
        formulationArtifact: XcircuiteFileReference
    ) -> XcircuiteCircuitPlanningProblem {
        let goalsByID = goalsKeyedByID(formulation.goals)
        let formulationRef = XcircuitePlanningReference(
            refID: "repair-formulation",
            kind: "repair-plan-formulation",
            path: formulationArtifact.path,
            artifactID: formulationArtifact.artifactID,
            metadata: [
                "formulationID": .string(formulation.formulationID),
                "intentID": .string(formulation.intentID),
                "intent": .string(formulation.intent),
            ]
        )
        let objectives = formulation.goals.map { goal in
            var evidence = goal.evidence
            evidence["formulationID"] = .string(formulation.formulationID)
            evidence["formulationGoalID"] = .string(goal.goalID)
            if !goal.symbolicGoalAtoms.isEmpty {
                evidence["symbolicGoalAtoms"] = .array(goal.symbolicGoalAtoms.map { .string($0) })
            }
            return XcircuitePlanningObjective(
                objectiveID: goal.goalID,
                kind: goal.kind,
                domain: goal.domain,
                priority: goal.priority,
                sourceRefIDs: unique(["repair-formulation"] + goal.sourceRefIDs),
                target: goal.target,
                currentValue: goal.currentValue,
                requiredValue: goal.requiredValue,
                unit: goal.unit,
                description: goal.description,
                evidence: evidence,
                suggestedActions: goal.suggestedActions
            )
        }
        let candidateActions = formulation.actions.map { action in
            var parameterHints = action.parameterHints
            parameterHints["formulationID"] = .string(formulation.formulationID)
            mergeStringArray(
                key: "satisfiesGoalAtoms",
                values: action.sourceGoalIDs.flatMap { goalsByID[$0]?.symbolicGoalAtoms ?? [] },
                into: &parameterHints
            )
            return XcircuitePlanningCandidateAction(
                actionID: action.actionID,
                domainID: action.domainID,
                operationID: action.operationID,
                maturity: action.maturity,
                reason: action.reason,
                sourceObjectiveIDs: action.sourceGoalIDs,
                requiredInputRefs: action.requiredInputRefs,
                verificationGates: action.verificationGates,
                parameterHints: parameterHints
            )
        }
        return XcircuiteCircuitPlanningProblem(
            problemID: problemID,
            runID: formulation.runID,
            sourceRefs: [formulationRef] + formulation.sourceRefs,
            initialStateRefs: formulation.initialStateRefs,
            assumptions: generatedAssumptions(for: formulation),
            riskClassifications: formulation.riskClassifications,
            objectives: objectives,
            constraints: resolvedConstraints(for: formulation),
            actionDomainRefs: resolvedActionDomainRefs(for: formulation),
            candidateActions: candidateActions,
            costModel: formulation.costModel ?? defaultCostModel(),
            verificationGates: resolvedVerificationGates(for: formulation),
            resumeContract: formulation.resumeContract ?? defaultResumeContract()
        )
    }

    private func generatedAssumptions(
        for formulation: XcircuiteRepairPlanFormulation
    ) -> [XcircuitePlanningAssumption] {
        [
            XcircuitePlanningAssumption(
                assumptionID: "repair-formulation-compiler-contract",
                source: "xcircuite.formulate-repair-planning-problem",
                statement: "Structured repair formulation was compiled without changing referenced design artifacts.",
                status: "resolved",
                confidence: 1,
                sourceRefIDs: ["repair-formulation"],
                requiredBeforeExecution: false,
                evidence: [
                    "formulationID": .string(formulation.formulationID),
                    "intentID": .string(formulation.intentID),
                ]
            ),
        ] + formulation.assumptions
    }

    private func resolvedActionDomainRefs(
        for formulation: XcircuiteRepairPlanFormulation
    ) -> [String] {
        unique(formulation.actionDomainRefs + formulation.actions.map(\.domainID))
    }

    private func resolvedVerificationGates(
        for formulation: XcircuiteRepairPlanFormulation
    ) -> [XcircuitePlanningVerificationGate] {
        var gates = formulation.verificationGates
        let existing = Set(gates.map(\.gateID))
        let missingGateIDs = unique(formulation.actions.flatMap(\.verificationGates))
            .filter { !existing.contains($0) }
        gates.append(contentsOf: missingGateIDs.map {
            XcircuitePlanningVerificationGate(
                gateID: $0,
                required: true,
                description: "Generated verification gate declaration for repair formulation action requirement \($0)."
            )
        })
        return gates
    }

    private func resolvedConstraints(
        for formulation: XcircuiteRepairPlanFormulation
    ) -> [XcircuitePlanningConstraint] {
        let generated = generatedTraceabilityConstraints(for: formulation)
        var constraints = formulation.constraints
        let existingIDs = Set(constraints.map(\.constraintID))
        constraints.append(contentsOf: generated.filter { !existingIDs.contains($0.constraintID) })
        return constraints
    }

    private func generatedTraceabilityConstraints(
        for formulation: XcircuiteRepairPlanFormulation
    ) -> [XcircuitePlanningConstraint] {
        let sourceRefIDs = unique(formulation.goals.flatMap(\.sourceRefIDs))
        guard !sourceRefIDs.isEmpty else {
            return []
        }
        let gateIDs = unique(formulation.actions.flatMap(\.verificationGates))
        return [
            XcircuitePlanningConstraint(
                constraintID: "repair-formulation-source-diagnostics-must-be-verified",
                kind: "verification",
                severity: "error",
                description: "Compiled repair plans must verify every diagnostic source that drove a formulation goal.",
                sourceRefIDs: sourceRefIDs,
                evidence: [
                    "formulationID": .string(formulation.formulationID),
                    "verificationGates": .array(gateIDs.map { .string($0) }),
                ]
            ),
        ]
    }

    private func defaultCostModel() -> XcircuitePlanningCostModel {
        XcircuitePlanningCostModel(
            strategy: "repair-formulation-declared-order",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "formulation.action-count",
                    weight: 1,
                    direction: "minimize",
                    description: "Prefer fewer candidate actions when formulation does not provide a calibrated cost model."
                ),
            ]
        )
    }

    private func defaultResumeContract() -> XcircuitePlanningResumeContract {
        XcircuitePlanningResumeContract(
            mode: "run-ledger",
            requiredArtifacts: [
                XcircuitePlanningArtifactStore.repairPlanFormulationRelativePath,
                XcircuitePlanningArtifactStore.problemRelativePath,
            ],
            blockedStates: ["formulation-validation-failed", "candidate-rejected"]
        )
    }

    private func diagnostics(for formulation: XcircuiteRepairPlanFormulation) -> [String] {
        var result: [String] = []
        if formulation.costModel == nil {
            result.append("default-cost-model-applied")
        }
        if formulation.resumeContract == nil {
            result.append("default-resume-contract-applied")
        }
        let declaredGateIDs = Set(formulation.verificationGates.map(\.gateID))
        if formulation.actions.flatMap(\.verificationGates).contains(where: { !declaredGateIDs.contains($0) }) {
            result.append("verification-gates-generated")
        }
        return result
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func firstDuplicate<T: Hashable>(_ values: [T]) -> T? {
        var seen: Set<T> = []
        for value in values {
            if !seen.insert(value).inserted {
                return value
            }
        }
        return nil
    }

    private func validateUniqueArtifactIDs(
        _ values: [String],
        validator: XcircuiteIdentifierValidator,
        duplicateError: (String) -> XcircuiteRepairPlanFormulationCompilationError
    ) throws {
        for value in values {
            try validator.validate(value, kind: .artifactID)
        }
        if let duplicateValue = firstDuplicate(values) {
            throw duplicateError(duplicateValue)
        }
    }

    private func goalsKeyedByID(
        _ goals: [XcircuiteRepairPlanFormulation.Goal]
    ) -> [String: XcircuiteRepairPlanFormulation.Goal] {
        var result: [String: XcircuiteRepairPlanFormulation.Goal] = [:]
        for goal in goals where result[goal.goalID] == nil {
            result[goal.goalID] = goal
        }
        return result
    }

    private func mergeStringArray(
        key: String,
        values: [String],
        into dictionary: inout [String: XcircuiteJSONValue]
    ) {
        let merged = unique(stringArrayValue(for: key, in: dictionary) + values)
        if !merged.isEmpty {
            dictionary[key] = .array(merged.map { .string($0) })
        }
    }

    private func stringArrayValue(
        for key: String,
        in values: [String: XcircuiteJSONValue]
    ) -> [String] {
        guard case .array(let array)? = values[key] else {
            return []
        }
        return array.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
    }
}
