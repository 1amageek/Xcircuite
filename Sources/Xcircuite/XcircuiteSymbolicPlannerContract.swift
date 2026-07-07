import XcircuitePackage

public struct XcircuiteSymbolicPlannerContract: Sendable {
    public init() {}

    public func evaluation(
        for step: XcircuiteCandidatePlanStep,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        symbolicStateBefore: [String] = []
    ) -> XcircuiteSymbolicPlannerStepEvaluation {
        let availableInputRefs = step.requiredInputRefs.filter { !step.missingInputRefs.contains($0) }
        let stateBefore = unique(
            symbolicStateBefore
                + availableInputRefs.map { "ref:\($0)" }
                + symbolicStateAtoms(from: step.parameterHints)
        )
        guard let domain = actionDomainSnapshot.domains.first(where: { $0.domainID == step.domainID }) else {
            return XcircuiteSymbolicPlannerStepEvaluation(
                domainID: step.domainID,
                operationID: step.operationID,
                actionDomainSupported: false,
                operationSupported: false,
                stepRequiredInputRefs: step.requiredInputRefs,
                stepMissingInputRefs: step.missingInputRefs,
                stateBefore: stateBefore,
                stateAfter: stateBefore,
                bindingStatus: "unsupported-action-domain"
            )
        }
        guard let operation = domain.operations.first(where: { $0.operationID == step.operationID }) else {
            return XcircuiteSymbolicPlannerStepEvaluation(
                domainID: step.domainID,
                operationID: step.operationID,
                actionDomainSupported: true,
                operationSupported: false,
                stepRequiredInputRefs: step.requiredInputRefs,
                stepMissingInputRefs: step.missingInputRefs,
                stateBefore: stateBefore,
                stateAfter: stateBefore,
                bindingStatus: "unsupported-operation"
            )
        }

        let requiredOperationInputRefs = operation.inputRefs.filter { !isOptionalOperationInputRef($0) }
        let optionalOperationInputRefs = operation.inputRefs.filter { isOptionalOperationInputRef($0) }
        let boundOperationInputRefs = operation.inputRefs.filter { operationInputRef in
            step.requiredInputRefs.contains(operationInputRef)
        }
        let unboundOperationInputRefs = requiredOperationInputRefs.filter { operationInputRef in
            !step.requiredInputRefs.contains(operationInputRef)
        }
        let activePreconditions = XcircuiteSymbolicPreconditionResolver().activePreconditions(
            for: operation,
            boundInputRefs: availableInputRefs,
            symbolicState: stateBefore
        )
        let satisfiedPreconditions = activePreconditions.filter { stateBefore.contains($0) }
        let unsatisfiedPreconditions = activePreconditions.filter { !stateBefore.contains($0) }
        let appliedEffects = unique(
            operation.effects
                + symbolicEffectAtoms(from: step.parameterHints)
        )
        let stateAfter = unique(
            stateBefore
                + appliedEffects
                + operation.producedArtifacts.map { "artifact:\($0)" }
        )
        let bindingStatus: String
        if !step.missingInputRefs.isEmpty {
            bindingStatus = "missing-step-input-refs"
        } else if unboundOperationInputRefs.isEmpty && unsatisfiedPreconditions.isEmpty {
            bindingStatus = "bound"
        } else if unboundOperationInputRefs.isEmpty {
            bindingStatus = "preconditions-unproven"
        } else {
            bindingStatus = "partially-bound"
        }

        return XcircuiteSymbolicPlannerStepEvaluation(
            domainID: step.domainID,
            operationID: step.operationID,
            actionDomainSupported: true,
            operationSupported: true,
            operationMaturity: operation.maturity,
            operationReversible: operation.reversible,
            stepRequiredInputRefs: step.requiredInputRefs,
            stepMissingInputRefs: step.missingInputRefs,
            operationInputRefs: operation.inputRefs,
            optionalOperationInputRefs: optionalOperationInputRefs,
            boundOperationInputRefs: boundOperationInputRefs,
            unboundOperationInputRefs: unboundOperationInputRefs,
            preconditions: activePreconditions,
            satisfiedPreconditions: satisfiedPreconditions,
            unsatisfiedPreconditions: unsatisfiedPreconditions,
            effects: operation.effects,
            appliedEffects: appliedEffects,
            producedArtifacts: operation.producedArtifacts,
            verificationGates: operation.verificationGates,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            bindingStatus: bindingStatus
        )
    }

    public func diagnostics(
        for step: XcircuiteCandidatePlanStep,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        symbolicStateBefore: [String] = []
    ) -> [XcircuitePlanVerificationDiagnostic] {
        guard let domain = actionDomainSnapshot.domains.first(where: { $0.domainID == step.domainID }) else {
            return [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "unsupported-action-domain",
                    message: "Candidate plan step \(step.stepID) references unsupported action domain \(step.domainID).",
                    stepID: step.stepID
                ),
            ]
        }
        guard let operation = domain.operations.first(where: { $0.operationID == step.operationID }) else {
            return [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "unsupported-operation",
                    message: "Candidate plan step \(step.stepID) references unsupported operation \(step.domainID)/\(step.operationID).",
                    stepID: step.stepID
                ),
            ]
        }

        var diagnostics: [XcircuitePlanVerificationDiagnostic] = []
        if operation.maturity != step.maturity {
            diagnostics.append(
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "action-domain-maturity-mismatch",
                    message: "Candidate plan step \(step.stepID) declares \(step.domainID)/\(step.operationID) maturity \(step.maturity), but the action domain declares \(operation.maturity).",
                    stepID: step.stepID
                )
            )
        }
        if operation.maturity != "implemented" {
            diagnostics.append(
                XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "operation-not-implemented",
                    message: "operation-not-implemented:\(step.domainID)/\(step.operationID)",
                    stepID: step.stepID
                )
            )
        }
        let evaluation = evaluation(
            for: step,
            actionDomainSnapshot: actionDomainSnapshot,
            symbolicStateBefore: symbolicStateBefore
        )
        if !evaluation.unboundOperationInputRefs.isEmpty {
            diagnostics.append(
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "unbound-operation-input-refs",
                    message: "unbound-operation-input-refs:\(step.domainID)/\(step.operationID):\(evaluation.unboundOperationInputRefs.joined(separator: ","))",
                    stepID: step.stepID
                )
            )
        }
        if !evaluation.unsatisfiedPreconditions.isEmpty {
            diagnostics.append(
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "unproven-operation-preconditions",
                    message: "unproven-operation-preconditions:\(step.domainID)/\(step.operationID):\(evaluation.unsatisfiedPreconditions.joined(separator: ","))",
                    stepID: step.stepID
                )
            )
        }
        return diagnostics
    }

    private func symbolicStateAtoms(from hints: [String: XcircuiteJSONValue]) -> [String] {
        var atoms: [String] = []
        atoms.append(contentsOf: stringArrayValue(for: "symbolicStateAtoms", in: hints))
        atoms.append(contentsOf: stringArrayValue(for: "satisfiedPreconditions", in: hints))
        return unique(atoms)
    }

    private func symbolicEffectAtoms(from hints: [String: XcircuiteJSONValue]) -> [String] {
        unique(
            stringArrayValue(for: "symbolicEffects", in: hints)
                + stringArrayValue(for: "satisfiesGoalAtoms", in: hints)
                + stringArrayValue(for: "producedGoalAtoms", in: hints)
        )
    }

    private func stringArrayValue(
        for key: String,
        in hints: [String: XcircuiteJSONValue]
    ) -> [String] {
        guard case .array(let values)? = hints[key] else {
            return []
        }
        return values.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
    }

    private func isOptionalOperationInputRef(_ inputRef: String) -> Bool {
        inputRef.hasPrefix("optional-")
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
}
