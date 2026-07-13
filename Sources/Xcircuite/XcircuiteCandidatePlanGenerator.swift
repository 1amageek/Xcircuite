import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanGenerator: Sendable {
    struct SymbolicPolicySelection: Sendable, Hashable {
        var strategy: String
        var trace: XcircuiteSymbolicPlannerPolicyTrace
    }

    let packageStore: XcircuitePackageStore
    let artifactStore: XcircuitePlanningArtifactStore

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
    }

    public func generateCandidatePlan(
        request: XcircuiteCandidatePlanGenerationRequest,
        projectRoot: URL
    ) throws -> XcircuiteCandidatePlanGenerationResult {
        let build = try makeCandidatePlanBuild(request: request, projectRoot: projectRoot)
        let reference = try artifactStore.persistCandidatePlan(
            build.draft.plan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let traceReference = try artifactStore.persistSymbolicPlannerTrace(
            build.draft.trace,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteCandidatePlanGenerationResult(
            status: "generated",
            runID: request.runID,
            problemID: build.problem.problemID,
            planID: build.draft.plan.planID,
            executionReadiness: build.draft.plan.executionReadiness,
            problemPath: build.problemPath,
            candidatePlanArtifact: try requireFoundationArtifactReference(
                reference,
                field: "candidate-plan"
            ),
            problemTranslationAuditArtifact: try requireFoundationArtifactReference(
                build.problemTranslationAuditArtifact,
                field: "problem-translation-audit"
            ),
            actionDomainSnapshotArtifact: try requireFoundationArtifactReference(
                build.actionDomainSnapshotArtifact,
                field: "action-domain-snapshot"
            ),
            symbolicPlannerTrace: build.draft.trace,
            symbolicPlannerTraceArtifact: try requireFoundationArtifactReference(
                traceReference,
                field: "symbolic-planner-trace"
            )
        )
    }

    public func runSymbolicPlannerFamily(
        request: XcircuiteSymbolicPlannerFamilyRunRequest,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerFamilyRunResult {
        try validateFamilyRequest(request)
        try rejectExistingFamilyRunOutputs(request: request, projectRoot: projectRoot)
        let normalizedCalibrationPolicy = try normalizedCalibrationPolicy(request.calibrationPolicy)
        var candidates: [FamilyCandidateBuild] = []
        for (index, strategy) in request.strategies.enumerated() {
            let generationRequest = XcircuiteCandidatePlanGenerationRequest(
                runID: request.runID,
                problemArtifactID: request.problemArtifactID,
                problemPath: request.problemPath,
                rejectedPlansArtifactID: request.rejectedPlansArtifactID,
                rejectedPlansPath: request.rejectedPlansPath,
                metricThresholdProfileArtifactID: request.metricThresholdProfileArtifactID,
                metricThresholdProfilePath: request.metricThresholdProfilePath,
                costCalibrationArtifactID: request.costCalibrationArtifactID,
                costCalibrationPath: request.costCalibrationPath,
                paretoCandidatesArtifactID: request.paretoCandidatesArtifactID,
                paretoCandidatesPath: request.paretoCandidatesPath,
                strategy: strategy,
                calibrationPolicy: request.calibrationPolicy
            )
            let build = try makeCandidatePlanBuild(request: generationRequest, projectRoot: projectRoot)
            let artifacts = try persistFamilyCandidateArtifacts(
                build: build,
                requestedStrategy: strategy,
                candidateIndex: index,
                familyRunID: request.familyRunID,
                projectRoot: projectRoot
            )
            let scoreComponents = familySelectionScoreComponents(
                plan: build.draft.plan,
                trace: build.draft.trace,
                candidateIndex: index
            )
            let selectionScore = scoreComponents.reduce(0) { $0 + $1.contribution }
            candidates.append(
                FamilyCandidateBuild(
                    build: build,
                    requestedStrategy: strategy,
                    candidateIndex: index,
                    selectionScore: selectionScore,
                    scoreComponents: scoreComponents,
                    candidatePlanArtifact: artifacts.plan,
                    symbolicPlannerTraceArtifact: artifacts.trace
                )
            )
        }
        let selected = try selectedFamilyCandidate(
            candidates,
            selectionPolicy: request.selectionPolicy
        )
        let promotedPlanArtifact = try artifactStore.persistCandidatePlan(
            selected.build.draft.plan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let promotedTraceArtifact = try artifactStore.persistSymbolicPlannerTrace(
            selected.build.draft.trace,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let candidateResults = try candidates.map { candidate in
            try familyCandidateResult(from: candidate, selectedCandidateIndex: selected.candidateIndex)
        }
        let familyRun = XcircuiteSymbolicPlannerFamilyRun(
            status: "generated",
            runID: request.runID,
            familyRunID: request.familyRunID,
            problemID: selected.build.problem.problemID,
            problemPath: selected.build.problemPath,
            selectionPolicy: request.selectionPolicy,
            calibrationPolicy: normalizedCalibrationPolicy,
            requestedStrategies: request.strategies,
            selectedCandidateIndex: selected.candidateIndex,
            selectedStrategy: selected.build.draft.trace.strategy,
            selectedPlanID: selected.build.draft.plan.planID,
            selectedCandidatePlanArtifact: try requireFoundationArtifactReference(
                selected.candidatePlanArtifact,
                field: "familyRun.selectedCandidatePlanArtifact"
            ),
            selectedSymbolicPlannerTraceArtifact: try requireFoundationArtifactReference(
                selected.symbolicPlannerTraceArtifact,
                field: "familyRun.selectedSymbolicPlannerTraceArtifact"
            ),
            promotedCandidatePlanArtifact: try requireFoundationArtifactReference(
                promotedPlanArtifact,
                field: "familyRun.promotedCandidatePlanArtifact"
            ),
            promotedSymbolicPlannerTraceArtifact: try requireFoundationArtifactReference(
                promotedTraceArtifact,
                field: "familyRun.promotedSymbolicPlannerTraceArtifact"
            ),
            candidates: candidateResults,
            diagnostics: familyDiagnostics(from: candidateResults)
        )
        let familyRunArtifact = try artifactStore.persistSymbolicPlannerFamilyRun(
            familyRun,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerFamilyRunResult(
            status: "generated",
            familyRun: familyRun,
            familyRunArtifact: try requireFoundationArtifactReference(
                familyRunArtifact,
                field: "familyRun.familyRunArtifact"
            )
        )
    }

    public func makeCandidatePlan(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        strategy: String = "first-ready-action-per-objective"
    ) throws -> XcircuiteCandidatePlan {
        try makeCandidatePlanDraft(
            problem: problem,
            problemPath: problemPath,
            strategy: strategy,
            rejectedPlanFeedback: emptyRejectedPlanFeedback(runID: problem.runID),
            calibrationContext: nil,
            policyTrace: nil
        ).plan
    }

    struct CandidatePlanDraft {
        var plan: XcircuiteCandidatePlan
        var trace: XcircuiteSymbolicPlannerTrace
    }

    struct CandidatePlanBuild {
        var problem: XcircuiteCircuitPlanningProblem
        var problemPath: String
        var draft: CandidatePlanDraft
        var problemTranslationAuditArtifact: XcircuiteFileReference
        var actionDomainSnapshotArtifact: XcircuiteFileReference
    }

    struct FamilyCandidateArtifacts {
        var plan: XcircuiteFileReference
        var trace: XcircuiteFileReference
    }

    struct FamilyCandidateBuild {
        var build: CandidatePlanBuild
        var requestedStrategy: String
        var candidateIndex: Int
        var selectionScore: Int
        var scoreComponents: [XcircuiteSymbolicPlannerFamilySelectionScoreComponent]
        var candidatePlanArtifact: XcircuiteFileReference
        var symbolicPlannerTraceArtifact: XcircuiteFileReference
    }

    struct CandidatePlanSequence {
        var steps: [XcircuiteCandidatePlanStep] = []
        var unresolvedObjectives: [String] = []
        var planBlockers: [String] = []
        var initialSymbolicState: [String] = []
        var finalSymbolicState: [String] = []
        var objectiveTraces: [XcircuiteSymbolicPlannerObjectiveTrace] = []
    }

    struct IndexedObjective {
        var index: Int
        var objective: XcircuitePlanningObjective
    }

    struct ObjectiveDecision {
        var indexedObjective: IndexedObjective
        var selectedEvaluation: SymbolicActionEvaluation?
        var actionTraces: [XcircuiteSymbolicPlannerActionTrace]
    }

    struct SymbolicActionEvaluation {
        var action: XcircuitePlanningCandidateAction
        var domain: XcircuiteActionDomain?
        var operation: XcircuiteActionDomainOperation?
        var scoreComponents: [XcircuiteSymbolicPlannerScoreComponent]
        var missingInputRefs: [String]
        var objectiveGoalAtoms: [String]
        var candidateEffectAtoms: [String]
        var matchedObjectiveGoalAtoms: [String]
        var missingObjectiveGoalAtoms: [String]
        var symbolicStateBefore: [String]
        var symbolicStateAfter: [String]
        var operationPreconditions: [String]
        var satisfiedPreconditionAtoms: [String]
        var unsatisfiedPreconditionAtoms: [String]
        var blockers: [String]

        var score: Int {
            scoreComponents.reduce(0) { $0 + $1.contribution }
        }

        var rejectedFeedbackScoreDelta: Int {
            scoreComponents.reduce(0) { total, component in
                component.termID.hasPrefix("feedback.") ? total + component.contribution : total
            }
        }

        var scoreBeforeRejectedFeedback: Int {
            score - rejectedFeedbackScoreDelta
        }
    }

    struct ActionDomainSnapshotContext {
        var snapshot: XcircuitePlanningActionDomainSnapshot
        var reference: XcircuiteFileReference
    }

    struct SymbolicCalibrationContext {
        var thresholdProfilePath: String?
        var thresholdProfile: XcircuiteMetricThresholdProfile?
        var costCalibrationPath: String?
        var costCalibration: XcircuiteCostCalibrationReport?
        var paretoCandidatesPath: String?
        var paretoCandidates: [XcircuiteParetoCandidateSet.Candidate]
        var calibratedTermsByGateID: [String: XcircuiteCostCalibrationReport.Term]
        var paretoCandidatesBySourceID: [String: [XcircuiteParetoCandidateSet.Candidate]]

        init(
            thresholdProfilePath: String?,
            thresholdProfile: XcircuiteMetricThresholdProfile?,
            costCalibrationPath: String?,
            costCalibration: XcircuiteCostCalibrationReport?,
            paretoCandidatesPath: String?,
            paretoCandidates: [XcircuiteParetoCandidateSet.Candidate]
        ) {
            self.thresholdProfilePath = thresholdProfilePath
            self.thresholdProfile = thresholdProfile
            self.costCalibrationPath = costCalibrationPath
            self.costCalibration = costCalibration
            self.paretoCandidatesPath = paretoCandidatesPath
            self.paretoCandidates = paretoCandidates
            var termsByGateID: [String: XcircuiteCostCalibrationReport.Term] = [:]
            for term in costCalibration?.calibratedTerms ?? [] {
                guard let gateID = term.gateID else {
                    continue
                }
                termsByGateID[gateID] = term
            }
            self.calibratedTermsByGateID = termsByGateID
            var candidatesBySourceID: [String: [XcircuiteParetoCandidateSet.Candidate]] = [:]
            for candidate in paretoCandidates {
                candidatesBySourceID[candidate.candidateID, default: []].append(candidate)
                if let sourceCandidateID = candidate.sourceCandidateID {
                    candidatesBySourceID[sourceCandidateID, default: []].append(candidate)
                }
            }
            self.paretoCandidatesBySourceID = candidatesBySourceID
        }

        func paretoCandidates(
            matching action: XcircuitePlanningCandidateAction
        ) -> [XcircuiteParetoCandidateSet.Candidate] {
            unique(
                (paretoCandidatesBySourceID[action.actionID] ?? [])
                    + (paretoCandidatesBySourceID[action.operationID] ?? [])
            )
        }

        func trace(
            strategy: String,
            objectiveTraces: [XcircuiteSymbolicPlannerObjectiveTrace]
        ) -> XcircuiteSymbolicPlannerCalibrationTrace {
            let actionTraces = objectiveTraces.flatMap(\.candidateActions)
            let appliedActionTraces = actionTraces.filter { actionTrace in
                actionTrace.scoreComponents.contains {
                    $0.termID.hasPrefix("cp7.")
                }
            }
            let matchedGateIDs = unique(
                appliedActionTraces.flatMap { actionTrace in
                    actionTrace.verificationGates.filter { gateID in
                        actionTrace.scoreComponents.contains {
                            $0.termID.contains(gateID) || $0.reason.contains(gateID)
                        }
                    }
                }
            )
            return XcircuiteSymbolicPlannerCalibrationTrace(
                strategy: strategy,
                metricThresholdProfilePath: thresholdProfilePath,
                costCalibrationPath: costCalibrationPath,
                paretoCandidatesPath: paretoCandidatesPath,
                thresholdCount: thresholdProfile?.thresholds.count ?? 0,
                calibratedTermCount: costCalibration?.calibratedTerms.count ?? 0,
                observationCount: costCalibration?.observations.count ?? 0,
                paretoCandidateCount: paretoCandidates.count,
                appliedActionCount: appliedActionTraces.count,
                matchedActionIDs: unique(appliedActionTraces.map(\.actionID)),
                matchedGateIDs: matchedGateIDs,
                diagnostics: diagnostics()
            )
        }

        private func diagnostics() -> [String] {
            var diagnostics: [String] = []
            if costCalibrationPath == nil {
                diagnostics.append("cost calibration artifact was not available")
            }
            if paretoCandidatesPath == nil {
                diagnostics.append("pareto candidate artifact was not available")
            }
            return diagnostics
        }

        private func unique(_ candidates: [XcircuiteParetoCandidateSet.Candidate]) -> [XcircuiteParetoCandidateSet.Candidate] {
            var seen: Set<String> = []
            var result: [XcircuiteParetoCandidateSet.Candidate] = []
            for candidate in candidates where seen.insert(candidate.candidateID).inserted {
                result.append(candidate)
            }
            return result
        }

        private func unique(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            var result: [String] = []
            for value in values where seen.insert(value).inserted {
                result.append(value)
            }
            return result
        }
    }
}
