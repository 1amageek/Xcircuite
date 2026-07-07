import Foundation
import XcircuitePackage

extension XcircuiteCandidatePlanGenerator {
    func makeActionTrace(
        rank: Int,
        rankBeforeRejectedFeedback: Int,
        evaluation: SymbolicActionEvaluation,
        selectedEvaluation: SymbolicActionEvaluation?
    ) -> XcircuiteSymbolicPlannerActionTrace {
        let action = evaluation.action
        return XcircuiteSymbolicPlannerActionTrace(
            rank: rank,
            actionID: action.actionID,
            domainID: action.domainID,
            operationID: action.operationID,
            maturity: action.maturity,
            score: evaluation.score,
            scoreBeforeRejectedFeedback: evaluation.scoreBeforeRejectedFeedback,
            rejectedFeedbackScoreDelta: evaluation.rejectedFeedbackScoreDelta,
            rankBeforeRejectedFeedback: rankBeforeRejectedFeedback,
            rejectedFeedbackRankDelta: rank - rankBeforeRejectedFeedback,
            scoreComponents: evaluation.scoreComponents,
            requiredInputRefs: action.requiredInputRefs,
            missingInputRefs: evaluation.missingInputRefs,
            verificationGates: action.verificationGates,
            actionDomainSupported: evaluation.domain != nil,
            operationSupported: evaluation.operation != nil,
            operationMaturity: evaluation.operation?.maturity,
            operationReversible: evaluation.operation?.reversible,
            operationPreconditions: evaluation.operationPreconditions,
            operationEffects: evaluation.operation?.effects ?? [],
            operationProducedArtifacts: evaluation.operation?.producedArtifacts ?? [],
            operationVerificationGates: evaluation.operation?.verificationGates ?? [],
            objectiveGoalAtoms: evaluation.objectiveGoalAtoms,
            candidateEffectAtoms: evaluation.candidateEffectAtoms,
            matchedObjectiveGoalAtoms: evaluation.matchedObjectiveGoalAtoms,
            missingObjectiveGoalAtoms: evaluation.missingObjectiveGoalAtoms,
            symbolicStateBefore: evaluation.symbolicStateBefore,
            symbolicStateAfter: evaluation.symbolicStateAfter,
            satisfiedPreconditionAtoms: evaluation.satisfiedPreconditionAtoms,
            unsatisfiedPreconditionAtoms: evaluation.unsatisfiedPreconditionAtoms,
            selected: selectedEvaluation.map { action.actionID == $0.action.actionID } ?? false,
            blockedReasons: evaluation.blockers,
            reason: action.reason
        )
    }

    func indexedObjectives(
        for objectives: [XcircuitePlanningObjective]
    ) -> [IndexedObjective] {
        objectives.enumerated().map { index, objective in
            IndexedObjective(index: index, objective: objective)
        }
    }

    func rankActionEvaluations(
        _ evaluations: [SymbolicActionEvaluation]
    ) -> [SymbolicActionEvaluation] {
        evaluations.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.action.actionID < rhs.action.actionID
        }
    }

    func rankActionEvaluationsBeforeRejectedFeedback(
        _ evaluations: [SymbolicActionEvaluation]
    ) -> [SymbolicActionEvaluation] {
        evaluations.sorted { lhs, rhs in
            if lhs.scoreBeforeRejectedFeedback != rhs.scoreBeforeRejectedFeedback {
                return lhs.scoreBeforeRejectedFeedback > rhs.scoreBeforeRejectedFeedback
            }
            return lhs.action.actionID < rhs.action.actionID
        }
    }

    func ranksByActionID(
        _ evaluations: [SymbolicActionEvaluation]
    ) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: evaluations.enumerated().map { index, evaluation in
                (evaluation.action.actionID, index + 1)
            }
        )
    }

    func availableReferences(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [String: XcircuitePlanningReference] {
        var references: [String: XcircuitePlanningReference] = [:]
        for reference in problem.sourceRefs + problem.initialStateRefs {
            guard let existing = references[reference.refID] else {
                references[reference.refID] = reference
                continue
            }
            if !hasAddressablePayload(existing), hasAddressablePayload(reference) {
                references[reference.refID] = reference
            }
        }
        return references
    }

    func hasAddressablePayload(_ reference: XcircuitePlanningReference) -> Bool {
        reference.path != nil || reference.artifactID != nil
    }

    func actionEvaluation(
        for action: XcircuitePlanningCandidateAction,
        objective: XcircuitePlanningObjective,
        availableRefs: [String: XcircuitePlanningReference],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        symbolicStateBefore: [String],
        costModel: XcircuitePlanningCostModel,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) -> SymbolicActionEvaluation {
        let missingRefs = missingInputRefs(for: action, availableRefs: availableRefs)
        let domain = actionDomainSnapshot?.domains.first { $0.domainID == action.domainID }
        let operation = domain?.operations.first { $0.operationID == action.operationID }
        let effectiveMaturity = operation?.maturity ?? action.maturity
        let verificationGates = unique(action.verificationGates + (operation?.verificationGates ?? []))
        let feedbackVerificationGates = action.verificationGates.isEmpty ? verificationGates : action.verificationGates
        let stateBefore = unique(symbolicStateBefore + symbolicStateAtoms(from: action.parameterHints))
        let objectiveGoalAtoms = symbolicGoalAtoms(for: objective)
        let candidateEffectAtoms = candidateEffectAtoms(for: action, operation: operation)
        let matchedObjectiveGoalAtoms = objectiveGoalAtoms.filter { candidateEffectAtoms.contains($0) }
        let missingObjectiveGoalAtoms = objectiveGoalAtoms.filter { !candidateEffectAtoms.contains($0) }
        let boundInputRefs = action.requiredInputRefs.filter { !missingRefs.contains($0) }
        let operationPreconditions = operation.map {
            XcircuiteSymbolicPreconditionResolver().activePreconditions(
                for: $0,
                boundInputRefs: boundInputRefs,
                symbolicState: stateBefore
            )
        } ?? []
        let satisfiedPreconditionAtoms = operationPreconditions.filter { stateBefore.contains($0) }
        let unsatisfiedPreconditionAtoms = operationPreconditions.filter { !stateBefore.contains($0) }
        let stateAfter = unique(stateBefore + candidateEffectAtoms)
        let blockers = actionBlockers(
            for: action,
            domain: domain,
            operation: operation,
            missingRefs: missingRefs,
            actionDomainSnapshotLoaded: actionDomainSnapshot != nil
        )
        var components = scoreComponents(
            for: action,
            effectiveMaturity: effectiveMaturity,
            verificationGates: verificationGates,
            operation: operation,
            missingRefs: missingRefs,
            objectiveGoalAtoms: objectiveGoalAtoms,
            matchedObjectiveGoalAtoms: matchedObjectiveGoalAtoms,
            missingObjectiveGoalAtoms: missingObjectiveGoalAtoms,
            satisfiedPreconditionAtoms: satisfiedPreconditionAtoms,
            unsatisfiedPreconditionAtoms: unsatisfiedPreconditionAtoms,
            costModel: costModel,
            feedbackVerificationGates: feedbackVerificationGates,
            rejectedPlanFeedback: rejectedPlanFeedback,
            calibrationContext: calibrationContext
        )
        if actionDomainSnapshot != nil && domain == nil {
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "unsupported-action-domain",
                    contribution: -200,
                    reason: "Action domain \(action.domainID) is not present in the run action-domain snapshot."
                )
            )
        } else if domain != nil && operation == nil {
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "unsupported-operation",
                    contribution: -200,
                    reason: "Operation \(action.domainID)/\(action.operationID) is not present in the run action-domain snapshot."
                )
            )
        }
        if let operation, operation.maturity != action.maturity {
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "action-domain-maturity-mismatch",
                    contribution: -80,
                    reason: "Candidate declares maturity \(action.maturity), but the action domain declares \(operation.maturity)."
                )
            )
        }
        return SymbolicActionEvaluation(
            action: action,
            domain: domain,
            operation: operation,
            scoreComponents: components,
            missingInputRefs: missingRefs,
            objectiveGoalAtoms: objectiveGoalAtoms,
            candidateEffectAtoms: candidateEffectAtoms,
            matchedObjectiveGoalAtoms: matchedObjectiveGoalAtoms,
            missingObjectiveGoalAtoms: missingObjectiveGoalAtoms,
            symbolicStateBefore: stateBefore,
            symbolicStateAfter: stateAfter,
            operationPreconditions: operationPreconditions,
            satisfiedPreconditionAtoms: satisfiedPreconditionAtoms,
            unsatisfiedPreconditionAtoms: unsatisfiedPreconditionAtoms,
            blockers: blockers
        )
    }

    func scoreComponents(
        for action: XcircuitePlanningCandidateAction,
        effectiveMaturity: String,
        verificationGates: [String],
        operation: XcircuiteActionDomainOperation?,
        missingRefs: [String],
        objectiveGoalAtoms: [String],
        matchedObjectiveGoalAtoms: [String],
        missingObjectiveGoalAtoms: [String],
        satisfiedPreconditionAtoms: [String],
        unsatisfiedPreconditionAtoms: [String],
        costModel: XcircuitePlanningCostModel,
        feedbackVerificationGates: [String],
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) -> [XcircuiteSymbolicPlannerScoreComponent] {
        var components: [XcircuiteSymbolicPlannerScoreComponent] = []
        if effectiveMaturity == "implemented" {
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "maturity.implemented",
                    contribution: 100,
                    reason: "Implemented operations are eligible for execution without planner-side implementation work."
                )
            )
        } else {
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "maturity.\(effectiveMaturity)",
                    contribution: 0,
                    reason: "Non-implemented operation maturity is retained for traceability and later verification."
                )
            )
        }
        if !missingRefs.isEmpty {
            let penalty = -missingRefs.count * weightedPenalty(
                for: "missing-input-ref",
                in: costModel,
                defaultValue: 20
            )
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "missing-input-ref",
                    contribution: penalty,
                    reason: "Action is missing required input refs: \(missingRefs.joined(separator: ","))."
                )
            )
        }
        if verificationGates.contains("approval-gate") {
            let penalty = -weightedPenalty(for: "approval-cost", in: costModel, defaultValue: 5)
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "approval-cost",
                    contribution: penalty,
                    reason: "Action requires a human approval gate."
                )
            )
        }
        if action.domainID == "layout-edit" {
            let penalty = -weightedPenalty(for: "layout-churn", in: costModel, defaultValue: 0)
            if penalty != 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "layout-churn",
                        contribution: penalty,
                        reason: "Layout edit actions carry physical churn cost in the active cost model."
                    )
                )
            }
        }
        if verificationGates.contains("simulation-metric-gate") {
            let penalty = -weightedPenalty(for: "simulation-regression-risk", in: costModel, defaultValue: 0)
            if penalty != 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "simulation-regression-risk",
                        contribution: penalty,
                        reason: "Action must preserve simulation metric gates."
                    )
                )
            }
        }
        components.append(contentsOf: rejectedPlanFeedbackScoreComponents(
            actionID: action.actionID,
            verificationGates: feedbackVerificationGates,
            feedbackSummary: rejectedPlanFeedback,
            costModel: costModel
        ))
        components.append(contentsOf: calibrationScoreComponents(
            action: action,
            verificationGates: feedbackVerificationGates,
            calibrationContext: calibrationContext
        ))
        if operation?.reversible == false {
            let penalty = -weightedPenalty(for: "irreversible-risk", in: costModel, defaultValue: 10)
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "irreversible-risk",
                    contribution: penalty,
                    reason: "Action-domain operation is not marked reversible."
                )
            )
        }
        if !objectiveGoalAtoms.isEmpty {
            if !matchedObjectiveGoalAtoms.isEmpty {
                let reward = matchedObjectiveGoalAtoms.count
                    * weightedReward(for: "objective-goal-effect-match", in: costModel, defaultValue: 25)
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "objective-goal-effect-match",
                        contribution: reward,
                        reason: "Action effects satisfy objective goal atoms: \(matchedObjectiveGoalAtoms.joined(separator: ","))."
                    )
                )
            }
            if !missingObjectiveGoalAtoms.isEmpty {
                let penalty = -missingObjectiveGoalAtoms.count
                    * weightedPenalty(for: "objective-goal-effect-miss", in: costModel, defaultValue: 8)
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "objective-goal-effect-miss",
                        contribution: penalty,
                        reason: "Action effects do not directly satisfy objective goal atoms: \(missingObjectiveGoalAtoms.joined(separator: ","))."
                    )
                )
            }
        }
        if operation != nil {
            if !satisfiedPreconditionAtoms.isEmpty {
                let reward = satisfiedPreconditionAtoms.count
                    * weightedReward(for: "symbolic-precondition-satisfied", in: costModel, defaultValue: 10)
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "symbolic-precondition-satisfied",
                        contribution: reward,
                        reason: "Current symbolic state satisfies operation preconditions: \(satisfiedPreconditionAtoms.joined(separator: ","))."
                    )
                )
            }
            if !unsatisfiedPreconditionAtoms.isEmpty {
                let penalty = -unsatisfiedPreconditionAtoms.count
                    * weightedPenalty(for: "symbolic-precondition-unproven", in: costModel, defaultValue: 6)
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "symbolic-precondition-unproven",
                        contribution: penalty,
                        reason: "Current symbolic state does not prove operation preconditions: \(unsatisfiedPreconditionAtoms.joined(separator: ","))."
                    )
                )
            }
        }
        return components
    }

    func rejectedPlanFeedbackScoreComponents(
        actionID: String,
        verificationGates: [String],
        feedbackSummary: XcircuiteRejectedPlanFeedbackSummary,
        costModel: XcircuitePlanningCostModel
    ) -> [XcircuiteSymbolicPlannerScoreComponent] {
        guard let feedback = XcircuiteRejectedPlanGateFeedbackMatcher().matchedCandidateFeedback(
            candidateID: actionID,
            verificationGates: verificationGates,
            globalFeedback: feedbackSummary.globalFeedback
        ) else {
            return []
        }
        var components: [XcircuiteSymbolicPlannerScoreComponent] = []
        if !feedback.failedGateIDs.isEmpty {
            let penalty = -feedback.failedGateIDs.count * weightedPenalty(
                for: "feedback.global.failed-gate",
                in: costModel,
                defaultValue: 20
            )
            if penalty != 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "feedback.global.failed-gate",
                        contribution: penalty,
                        reason: "Global rejected-plan feedback matches action verification gates: \(feedback.failedGateIDs.joined(separator: ","))."
                    )
                )
            }
        }
        if !feedback.diagnosticCodes.isEmpty {
            let penalty = -feedback.diagnosticCodes.count * weightedPenalty(
                for: "feedback.global.diagnostic",
                in: costModel,
                defaultValue: 5
            )
            if penalty != 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "feedback.global.diagnostic",
                        contribution: penalty,
                        reason: "Global rejected-plan diagnostics match this action gate family: \(feedback.diagnosticCodes.joined(separator: ","))."
                    )
                )
            }
        }
        if !feedback.nextActions.isEmpty {
            let penalty = -feedback.nextActions.count * weightedPenalty(
                for: "feedback.global.next-action",
                in: costModel,
                defaultValue: 2
            )
            if penalty != 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "feedback.global.next-action",
                        contribution: penalty,
                        reason: "Global rejected-plan next actions still point at this action gate family: \(feedback.nextActions.joined(separator: ","))."
                    )
                )
            }
        }
        return components
    }

    func calibrationScoreComponents(
        action: XcircuitePlanningCandidateAction,
        verificationGates: [String],
        calibrationContext: SymbolicCalibrationContext?
    ) -> [XcircuiteSymbolicPlannerScoreComponent] {
        guard let calibrationContext else {
            return []
        }
        var components: [XcircuiteSymbolicPlannerScoreComponent] = []
        for gateID in verificationGates.sorted() {
            guard let term = calibrationContext.calibratedTermsByGateID[gateID] else {
                continue
            }
            let penalty = Int(max(0, term.calibratedWeight - term.baseWeight) * 10)
            guard penalty > 0 else {
                continue
            }
            components.append(
                XcircuiteSymbolicPlannerScoreComponent(
                    termID: "cp7.calibrated-gate.\(gateID)",
                    contribution: -penalty,
                    reason: "CP7 cost calibration term \(term.termID) demotes actions carrying gate \(gateID)."
                )
            )
        }
        for candidate in calibrationContext.paretoCandidates(matching: action) {
            let failedGateIDs = candidate.gateStatuses
                .filter { $0.value != "passed" }
                .map(\.key)
                .sorted()
            if !failedGateIDs.isEmpty {
                let gatePenalty = failedGateIDs.reduce(0) { total, gateID in
                    let termPenalty = calibrationContext.calibratedTermsByGateID[gateID].map {
                        Int(max(1, ($0.calibratedWeight - $0.baseWeight) * 10))
                    } ?? 5
                    return total + termPenalty
                }
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "cp7.pareto-failed-gates",
                        contribution: -gatePenalty,
                        reason: "CP7 Pareto candidate \(candidate.candidateID) failed gates \(failedGateIDs.joined(separator: ","))."
                    )
                )
            }
            let dominancePenalty = max(candidate.frontierRank - 1, 0) * 5
                + candidate.dominatedByCandidateIDs.count * 5
            if dominancePenalty > 0 {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "cp7.pareto-dominance",
                        contribution: -dominancePenalty,
                        reason: "CP7 Pareto candidate \(candidate.candidateID) is dominated or below the frontier."
                    )
                )
            }
            if !candidate.gateStatuses.isEmpty && failedGateIDs.isEmpty {
                components.append(
                    XcircuiteSymbolicPlannerScoreComponent(
                        termID: "cp7.pareto-passed-gates",
                        contribution: 5,
                        reason: "CP7 Pareto candidate \(candidate.candidateID) has passing gate status evidence."
                    )
                )
            }
        }
        return components
    }
}
