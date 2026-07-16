import Foundation
import DesignFlowKernel

extension XcircuiteCandidatePlanGenerator {
    func makeCandidatePlanDraft(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        strategy: String,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot? = nil,
        actionDomainSnapshotRef: ArtifactReference? = nil,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?,
        policyTrace: XcircuiteSymbolicPlannerPolicyTrace?
    ) throws -> CandidatePlanDraft {
        let planID = try identifier("\(problem.problemID)-candidate-plan-1")
        let availableRefs = availableReferences(for: problem)
        var sequence = try makeCandidatePlanSequence(
            problem: problem,
            planID: planID,
            strategy: strategy,
            availableRefs: availableRefs,
            actionDomainSnapshot: actionDomainSnapshot,
            rejectedPlanFeedback: rejectedPlanFeedback,
            calibrationContext: calibrationContext
        )
        let goalCoverage = goalCoverage(
            for: problem.objectives,
            finalSymbolicState: sequence.finalSymbolicState
        )
        let missingGoalAtoms = missingGoalAtomRefs(from: goalCoverage)
        sequence.planBlockers.append(contentsOf: goalCoverageBlockers(from: goalCoverage))

        let readiness: String
        if !sequence.unresolvedObjectives.isEmpty || sequence.planBlockers.contains(where: { isHardBlocker($0) }) {
            readiness = "blocked"
        } else if sequence.planBlockers.isEmpty {
            readiness = "ready"
        } else {
            readiness = "requires-implementation"
        }
        let reviewProjection = XcircuiteCandidatePlanReviewProjection()

        let plan = XcircuiteCandidatePlan(
            planID: planID,
            problemID: problem.problemID,
            runID: problem.runID,
            strategy: strategy,
            executionReadiness: readiness,
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: problemPath,
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            assumptions: reviewProjection.assumptions(from: problem),
            riskClassifications: reviewProjection.riskClassifications(
                from: problem,
                steps: sequence.steps
            ),
            steps: sequence.steps,
            verificationGates: problem.verificationGates,
            constraints: problem.constraints,
            unresolvedObjectives: sequence.unresolvedObjectives,
            blockers: sequence.planBlockers
        )
        let trace = XcircuiteSymbolicPlannerTrace(
            runID: problem.runID,
            problemID: problem.problemID,
            strategy: strategy,
            problemPath: problemPath,
            actionDomainSnapshotPath: actionDomainSnapshotRef?.path,
            actionDomainSnapshotArtifactID: actionDomainSnapshotRef?.artifactID,
            rejectedPlansPath: rejectedPlanFeedback.rejectedPlansPath,
            rejectedPlanFeedbackRecordCount: rejectedPlanFeedback.recordCount,
            globalRejectedPlanFeedbackCount: rejectedPlanFeedback.globalFeedback.count,
            policyTrace: policyTrace,
            calibrationTrace: calibrationContext?.trace(
                strategy: strategy,
                objectiveTraces: sequence.objectiveTraces
            ),
            generatedPlanID: plan.planID,
            selectedActionIDs: sequence.steps.map(\.actionID),
            unresolvedObjectiveIDs: sequence.unresolvedObjectives,
            initialSymbolicState: sequence.initialSymbolicState,
            finalSymbolicState: sequence.finalSymbolicState,
            goalCoverageStatus: goalCoverageStatus(from: goalCoverage),
            goalCoverage: goalCoverage,
            missingGoalAtoms: missingGoalAtoms,
            objectiveTraces: sequence.objectiveTraces
        )
        return CandidatePlanDraft(plan: plan, trace: trace)
    }

    func makeCandidatePlanSequence(
        problem: XcircuiteCircuitPlanningProblem,
        planID: String,
        strategy: String,
        availableRefs: [String: XcircuitePlanningReference],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) throws -> CandidatePlanSequence {
        if strategy == "state-aware-objective-ordering"
            || strategy == "calibrated-state-aware-objective-ordering" {
            return try makeStateAwareCandidatePlanSequence(
                problem: problem,
                planID: planID,
                availableRefs: availableRefs,
                actionDomainSnapshot: actionDomainSnapshot,
                rejectedPlanFeedback: rejectedPlanFeedback,
                calibrationContext: calibrationContext
            )
        }
        return try makeInputOrderCandidatePlanSequence(
            problem: problem,
            planID: planID,
            availableRefs: availableRefs,
            actionDomainSnapshot: actionDomainSnapshot,
            rejectedPlanFeedback: rejectedPlanFeedback,
            calibrationContext: calibrationContext
        )
    }

    func makeInputOrderCandidatePlanSequence(
        problem: XcircuiteCircuitPlanningProblem,
        planID: String,
        availableRefs: [String: XcircuitePlanningReference],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) throws -> CandidatePlanSequence {
        var sequence = CandidatePlanSequence()
        var symbolicState = initialSymbolicState(for: problem)
        sequence.initialSymbolicState = symbolicState
        sequence.finalSymbolicState = symbolicState
        for indexedObjective in indexedObjectives(for: problem.objectives) {
            let decision = objectiveDecision(
                for: indexedObjective,
                problem: problem,
                availableRefs: availableRefs,
                actionDomainSnapshot: actionDomainSnapshot,
                symbolicState: symbolicState,
                rejectedPlanFeedback: rejectedPlanFeedback,
                calibrationContext: calibrationContext
            )
            try appendObjectiveDecision(
                decision,
                planID: planID,
                sequence: &sequence,
                symbolicState: &symbolicState
            )
        }
        return sequence
    }

    func makeStateAwareCandidatePlanSequence(
        problem: XcircuiteCircuitPlanningProblem,
        planID: String,
        availableRefs: [String: XcircuitePlanningReference],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) throws -> CandidatePlanSequence {
        var sequence = CandidatePlanSequence()
        var symbolicState = initialSymbolicState(for: problem)
        sequence.initialSymbolicState = symbolicState
        sequence.finalSymbolicState = symbolicState
        var pendingObjectives = indexedObjectives(for: problem.objectives)
        while !pendingObjectives.isEmpty {
            let decisions = pendingObjectives.map { indexedObjective in
                objectiveDecision(
                    for: indexedObjective,
                    problem: problem,
                    availableRefs: availableRefs,
                    actionDomainSnapshot: actionDomainSnapshot,
                    symbolicState: symbolicState,
                    rejectedPlanFeedback: rejectedPlanFeedback,
                    calibrationContext: calibrationContext
                )
            }
            let selectedDecision = try bestObjectiveDecision(decisions)
            try appendObjectiveDecision(
                selectedDecision,
                planID: planID,
                sequence: &sequence,
                symbolicState: &symbolicState
            )
            pendingObjectives.removeAll {
                $0.index == selectedDecision.indexedObjective.index
            }
        }
        return sequence
    }

    func objectiveDecision(
        for indexedObjective: IndexedObjective,
        problem: XcircuiteCircuitPlanningProblem,
        availableRefs: [String: XcircuitePlanningReference],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?,
        symbolicState: [String],
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary,
        calibrationContext: SymbolicCalibrationContext?
    ) -> ObjectiveDecision {
        let objective = indexedObjective.objective
        let actionEvaluations = problem.candidateActions
            .filter { $0.sourceObjectiveIDs.contains(objective.objectiveID) }
            .map {
                actionEvaluation(
                    for: $0,
                    objective: objective,
                    availableRefs: availableRefs,
                    actionDomainSnapshot: actionDomainSnapshot,
                    symbolicStateBefore: symbolicState,
                    costModel: problem.costModel,
                    rejectedPlanFeedback: rejectedPlanFeedback,
                    calibrationContext: calibrationContext
                )
            }
        let rankedActionEvaluations = rankActionEvaluations(actionEvaluations)
        let ranksBeforeRejectedFeedback = ranksByActionID(
            rankActionEvaluationsBeforeRejectedFeedback(actionEvaluations)
        )
        let selectedEvaluation = rankedActionEvaluations.first
        let actionTraces = rankedActionEvaluations.enumerated().map { index, evaluation in
            makeActionTrace(
                rank: index + 1,
                rankBeforeRejectedFeedback: ranksBeforeRejectedFeedback[evaluation.action.actionID] ?? index + 1,
                evaluation: evaluation,
                selectedEvaluation: selectedEvaluation
            )
        }
        return ObjectiveDecision(
            indexedObjective: indexedObjective,
            selectedEvaluation: selectedEvaluation,
            actionTraces: actionTraces
        )
    }

    func bestObjectiveDecision(
        _ decisions: [ObjectiveDecision]
    ) throws -> ObjectiveDecision {
        guard let best = decisions.sorted(by: shouldRankBefore).first else {
            throw XcircuiteCandidatePlanGenerationError.noObjectives
        }
        return best
    }

    func shouldRankBefore(
        lhs: ObjectiveDecision,
        rhs: ObjectiveDecision
    ) -> Bool {
        let lhsReadiness = readinessRank(for: lhs.selectedEvaluation)
        let rhsReadiness = readinessRank(for: rhs.selectedEvaluation)
        if lhsReadiness != rhsReadiness {
            return lhsReadiness > rhsReadiness
        }
        let lhsScore = lhs.selectedEvaluation?.score ?? Int.min
        let rhsScore = rhs.selectedEvaluation?.score ?? Int.min
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return lhs.indexedObjective.index < rhs.indexedObjective.index
    }

    func readinessRank(
        for evaluation: SymbolicActionEvaluation?
    ) -> Int {
        guard let evaluation else {
            return 0
        }
        if evaluation.blockers.isEmpty {
            return 3
        }
        if evaluation.blockers.contains(where: isHardBlocker) {
            return 1
        }
        return 2
    }

    func appendObjectiveDecision(
        _ decision: ObjectiveDecision,
        planID: String,
        sequence: inout CandidatePlanSequence,
        symbolicState: inout [String]
    ) throws {
        let objective = decision.indexedObjective.objective
        guard let selectedEvaluation = decision.selectedEvaluation else {
            let unresolvedReason = "no-candidate-action:\(objective.objectiveID)"
            sequence.unresolvedObjectives.append(objective.objectiveID)
            sequence.planBlockers.append(unresolvedReason)
            sequence.objectiveTraces.append(
                XcircuiteSymbolicPlannerObjectiveTrace(
                    objectiveID: objective.objectiveID,
                    unresolvedReason: unresolvedReason,
                    candidateActions: decision.actionTraces
                )
            )
            return
        }
        let selected = selectedEvaluation.action
        let blockers = selectedEvaluation.blockers
        let readiness = blockers.isEmpty ? "ready" : "blocked"
        sequence.steps.append(
            XcircuiteCandidatePlanStep(
                stepID: try identifier("\(planID)-step-\(sequence.steps.count + 1)"),
                order: sequence.steps.count + 1,
                actionID: selected.actionID,
                domainID: selected.domainID,
                operationID: selected.operationID,
                maturity: selected.maturity,
                readiness: readiness,
                sourceObjectiveIDs: selected.sourceObjectiveIDs,
                requiredInputRefs: selected.requiredInputRefs,
                missingInputRefs: selectedEvaluation.missingInputRefs,
                verificationGates: selected.verificationGates,
                reason: selected.reason,
                parameterHints: selected.parameterHints,
                blockers: blockers
            )
        )
        sequence.planBlockers.append(contentsOf: blockers.map { "\(objective.objectiveID):\($0)" })
        if blockers.isEmpty {
            symbolicState = selectedEvaluation.symbolicStateAfter
        }
        sequence.finalSymbolicState = symbolicState
        sequence.objectiveTraces.append(
            XcircuiteSymbolicPlannerObjectiveTrace(
                objectiveID: objective.objectiveID,
                selectedActionID: selected.actionID,
                candidateActions: decision.actionTraces
            )
        )
    }
}
