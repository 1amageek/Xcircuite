import Foundation
import DesignFlowKernel

public struct XcircuiteParameterCandidatePlanSynthesizer: Sendable {
    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func synthesizeCandidatePlan(
        request: XcircuiteParameterCandidatePlanSynthesisRequest,
        projectRoot: URL
    ) throws -> XcircuiteParameterCandidatePlanSynthesisResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        if let rank = request.rank, rank <= 0 {
            throw XcircuiteParameterCandidatePlanSynthesisError.invalidRank(rank)
        }
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let problemPath = try requiredPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .json,
            missingError: .missingProblemReference
        )
        let candidatesPath = try requiredPath(
            explicitPath: request.parameterCandidatesPath,
            artifactID: request.parameterCandidatesArtifactID ?? XcircuitePlanningArtifactStore.parameterCandidatesArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .text,
            missingError: .missingParameterCandidatesReference
        )
        let problem = try packageStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: packageStore.url(forProjectRelativePath: problemPath, inProjectAt: projectRoot)
        )
        guard problem.runID == request.runID else {
            throw XcircuiteParameterCandidatePlanSynthesisError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }
        let candidates = try readParameterCandidates(path: candidatesPath, projectRoot: projectRoot)
        let feedbackSummary = try loadRejectedPlanFeedback(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        let feedbackWeighting = try feedbackWeighting(from: problem.costModel)
        let selection = try selectCandidate(
            candidates,
            candidateID: request.candidateID,
            rank: request.rank,
            strategy: request.strategy,
            runID: request.runID,
            problemID: problem.problemID,
            parameterCandidatesPath: candidatesPath,
            feedbackSummary: feedbackSummary,
            feedbackWeighting: feedbackWeighting,
            includeRejectedCandidates: request.includeRejectedCandidates
        )
        let candidate = selection.candidate
        guard candidate.runID == request.runID else {
            throw XcircuiteParameterCandidatePlanSynthesisError.runMismatch(
                expected: request.runID,
                actual: candidate.runID
            )
        }
        guard candidate.problemID == problem.problemID else {
            throw XcircuiteParameterCandidatePlanSynthesisError.problemMismatch(
                expected: problem.problemID,
                actual: candidate.problemID
            )
        }
        guard let sourceAction = problem.candidateActions.first(where: { $0.actionID == candidate.sourceActionID }) else {
            throw XcircuiteParameterCandidatePlanSynthesisError.sourceActionNotFound(
                actionID: candidate.sourceActionID
            )
        }

        let plan = try makeCandidatePlan(
            problem: problem,
            problemPath: problemPath,
            candidatesPath: candidatesPath,
            candidate: candidate,
            sourceAction: sourceAction,
            strategy: request.strategy
        )
        let selectionTraceReference = try artifactStore.persistParameterCandidateSelectionTrace(
            selection.trace,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let reference = try artifactStore.persistCandidatePlan(plan, runID: request.runID, projectRoot: projectRoot)
        return XcircuiteParameterCandidatePlanSynthesisResult(
            status: "generated",
            runID: request.runID,
            problemID: problem.problemID,
            selectedCandidateID: candidate.candidateID,
            selectedCandidateRank: candidate.rank,
            planID: plan.planID,
            executionReadiness: plan.executionReadiness,
            problemPath: problemPath,
            parameterCandidatesPath: candidatesPath,
            rejectedPlanFeedback: feedbackSummary.recordCount > 0 ? feedbackSummary : nil,
            skippedRejectedCandidateIDs: selection.skippedRejectedCandidateIDs.isEmpty
                ? nil
                : selection.skippedRejectedCandidateIDs,
            selectionTrace: selection.trace,
            selectionTraceArtifact: selectionTraceReference,
            candidatePlanArtifact: reference
        )
    }

    public func makeCandidatePlan(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        candidatesPath: String,
        candidate: XcircuiteParameterCandidate,
        sourceAction: XcircuitePlanningCandidateAction,
        strategy: String = "parameter-candidate-to-netlist-edit"
    ) throws -> XcircuiteCandidatePlan {
        let planID = try identifier("\(problem.problemID)-\(candidate.candidateID)-edit-plan")
        let netlistRef = selectedNetlistReference(problem: problem, sourceAction: sourceAction)
        var blockers: [String] = []
        if netlistRef == nil {
            blockers.append("missing-input-ref:source-netlist")
        }
        let readiness = blockers.isEmpty ? "ready" : "blocked"
        let step = XcircuiteCandidatePlanStep(
            stepID: try identifier("\(planID)-step-1"),
            order: 1,
            actionID: "\(candidate.sourceActionID)-apply-\(candidate.rank)",
            domainID: "simulation-analysis",
            operationID: "simulation.set-netlist-parameters",
            maturity: "implemented",
            readiness: readiness,
            sourceObjectiveIDs: candidate.sourceObjectiveIDs,
            requiredInputRefs: [netlistRef?.refID ?? "source-netlist-ref"],
            missingInputRefs: netlistRef == nil ? ["source-netlist-ref"] : [],
            verificationGates: candidate.verificationGates,
            reason: "Apply parameter candidate \(candidate.candidateID) to a SPICE netlist for verification.",
            parameterHints: parameterHints(
                sourceAction: sourceAction,
                candidate: candidate,
                candidatesPath: candidatesPath,
                netlistRef: netlistRef
            ),
            blockers: blockers
        )
        let reviewProjection = XcircuiteCandidatePlanReviewProjection()
        return XcircuiteCandidatePlan(
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
                steps: [step]
            ),
            steps: [step],
            verificationGates: problem.verificationGates,
            constraints: problem.constraints,
            unresolvedObjectives: readiness == "ready" ? [] : candidate.sourceObjectiveIDs,
            blockers: blockers
        )
    }

    private func parameterHints(
        sourceAction: XcircuitePlanningCandidateAction,
        candidate: XcircuiteParameterCandidate,
        candidatesPath: String,
        netlistRef: XcircuitePlanningReference?
    ) -> [String: XcircuiteJSONValue] {
        var hints = sourceAction.parameterHints
        hints["sourceParameterCandidateID"] = .string(candidate.candidateID)
        hints["sourceParameterCandidateRank"] = .number(Double(candidate.rank))
        hints["sourceParameterCandidatesPath"] = .string(candidatesPath)
        hints["assignments"] = .array(candidate.assignments.map { assignment in
            var object: [String: XcircuiteJSONValue] = [
                "name": .string(assignment.name),
                "value": .number(assignment.value),
            ]
            if let unit = assignment.unit {
                object["unit"] = .string(unit)
            }
            return .object(object)
        })
        if let netlistRef {
            hints["netlistRef"] = .string(netlistRef.refID)
            if let path = netlistRef.path {
                hints["netlistPath"] = .string(path)
            }
            if let artifactID = netlistRef.artifactID {
                hints["netlistArtifactID"] = .string(artifactID)
            }
        }
        return hints
    }

    private func selectedNetlistReference(
        problem: XcircuiteCircuitPlanningProblem,
        sourceAction: XcircuitePlanningCandidateAction
    ) -> XcircuitePlanningReference? {
        let references = problem.sourceRefs + problem.initialStateRefs
        let explicitRefID = stringHint("netlistRef", sourceAction: sourceAction)
            ?? stringHint("netlistRefID", sourceAction: sourceAction)
            ?? stringHint("sourceNetlistRef", sourceAction: sourceAction)
        if let explicitRefID,
           let reference = references.first(where: { $0.refID == explicitRefID }) {
            return reference
        }
        for refID in sourceAction.requiredInputRefs {
            if let reference = references.first(where: { $0.refID == refID && isNetlist($0) }) {
                return reference
            }
        }
        return references.first(where: isNetlist)
    }

    private func isNetlist(_ reference: XcircuitePlanningReference) -> Bool {
        let kind = reference.kind.lowercased()
        return kind.contains("netlist") || kind.contains("spice")
    }

    private func stringHint(
        _ key: String,
        sourceAction: XcircuitePlanningCandidateAction
    ) -> String? {
        guard case .string(let value) = sourceAction.parameterHints[key] else {
            return nil
        }
        return value
    }

    private func selectCandidate(
        _ candidates: [XcircuiteParameterCandidate],
        candidateID: String?,
        rank: Int?,
        strategy: String,
        runID: String,
        problemID: String,
        parameterCandidatesPath: String,
        feedbackSummary: XcircuiteRejectedPlanFeedbackSummary,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting,
        includeRejectedCandidates: Bool
    ) throws -> ParameterCandidateSelection {
        let sorted = candidates.sorted {
            if $0.rank != $1.rank {
                return $0.rank < $1.rank
            }
            return $0.candidateID < $1.candidateID
        }
        let excludedCandidateIDs = Set(feedbackSummary.excludedCandidateIDs)
        let feedbackByCandidateID = Dictionary(
            uniqueKeysWithValues: feedbackSummary.candidateFeedback.map { ($0.candidateID, $0) }
        )
        if let candidateID,
           let candidate = sorted.first(where: { $0.candidateID == candidateID }) {
            try validateCandidateFeedback(
                candidate,
                excludedCandidateIDs: excludedCandidateIDs,
                feedbackSummary: feedbackSummary,
                includeRejectedCandidates: includeRejectedCandidates
            )
            return ParameterCandidateSelection(
                candidate: candidate,
                skippedRejectedCandidateIDs: [],
                trace: selectionTrace(
                    candidates: sorted,
                    feedbackByCandidateID: feedbackByCandidateID,
                    globalFeedback: feedbackSummary.globalFeedback,
                    selectedCandidateID: candidate.candidateID,
                    runID: runID,
                    problemID: problemID,
                    strategy: strategy,
                    parameterCandidatesPath: parameterCandidatesPath,
                    rejectedPlansPath: feedbackSummary.rejectedPlansPath,
                    feedbackWeighting: feedbackWeighting,
                    includeRejectedCandidates: includeRejectedCandidates,
                    explicitCandidateID: candidateID,
                    explicitRank: rank
                )
            )
        }
        if let rank,
           let candidate = sorted.first(where: { $0.rank == rank }) {
            try validateCandidateFeedback(
                candidate,
                excludedCandidateIDs: excludedCandidateIDs,
                feedbackSummary: feedbackSummary,
                includeRejectedCandidates: includeRejectedCandidates
            )
            return ParameterCandidateSelection(
                candidate: candidate,
                skippedRejectedCandidateIDs: [],
                trace: selectionTrace(
                    candidates: sorted,
                    feedbackByCandidateID: feedbackByCandidateID,
                    globalFeedback: feedbackSummary.globalFeedback,
                    selectedCandidateID: candidate.candidateID,
                    runID: runID,
                    problemID: problemID,
                    strategy: strategy,
                    parameterCandidatesPath: parameterCandidatesPath,
                    rejectedPlansPath: feedbackSummary.rejectedPlansPath,
                    feedbackWeighting: feedbackWeighting,
                    includeRejectedCandidates: includeRejectedCandidates,
                    explicitCandidateID: candidateID,
                    explicitRank: rank
                )
            )
        }
        if candidateID == nil, rank == nil {
            let scores = selectionScores(
                candidates: sorted,
                feedbackByCandidateID: feedbackByCandidateID,
                globalFeedback: feedbackSummary.globalFeedback,
                selectedCandidateID: nil,
                feedbackWeighting: feedbackWeighting,
                includeRejectedCandidates: includeRejectedCandidates
            )
            let scoreByCandidateID = Dictionary(uniqueKeysWithValues: scores.map { ($0.candidateID, $0) })
            let skipped = scores
                .filter { $0.selectionState == "excluded" }
                .map(\.candidateID)
            let eligibleCandidates = sorted.filter { candidate in
                scoreByCandidateID[candidate.candidateID]?.selectionState != "excluded"
            }
            if let candidate = eligibleCandidates.min(by: { lhs, rhs in
                candidateSelectionSort(
                    lhs: lhs,
                    rhs: rhs,
                    scoreByCandidateID: scoreByCandidateID
                )
            }) {
                return ParameterCandidateSelection(
                    candidate: candidate,
                    skippedRejectedCandidateIDs: skipped,
                    trace: selectionTrace(
                        candidates: sorted,
                        feedbackByCandidateID: feedbackByCandidateID,
                        globalFeedback: feedbackSummary.globalFeedback,
                        selectedCandidateID: candidate.candidateID,
                        runID: runID,
                        problemID: problemID,
                        strategy: strategy,
                        parameterCandidatesPath: parameterCandidatesPath,
                        rejectedPlansPath: feedbackSummary.rejectedPlansPath,
                        feedbackWeighting: feedbackWeighting,
                        includeRejectedCandidates: includeRejectedCandidates,
                        explicitCandidateID: nil,
                        explicitRank: nil
                    )
                )
            }
            if !skipped.isEmpty {
                throw XcircuiteParameterCandidatePlanSynthesisError.noEligibleCandidateAfterFeedback(
                    excludedCandidateIDs: skipped
                )
            }
        }
        throw XcircuiteParameterCandidatePlanSynthesisError.candidateNotFound(
            candidateID: candidateID,
            rank: rank
        )
    }

    private func candidateSelectionSort(
        lhs: XcircuiteParameterCandidate,
        rhs: XcircuiteParameterCandidate,
        scoreByCandidateID: [String: XcircuiteParameterCandidateSelectionScore]
    ) -> Bool {
        let lhsScore = scoreByCandidateID[lhs.candidateID]?.totalScore ?? lhs.normalizedCost
        let rhsScore = scoreByCandidateID[rhs.candidateID]?.totalScore ?? rhs.normalizedCost
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
        }
        if lhs.normalizedCost != rhs.normalizedCost {
            return lhs.normalizedCost < rhs.normalizedCost
        }
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        return lhs.candidateID < rhs.candidateID
    }

    private func selectionTrace(
        candidates: [XcircuiteParameterCandidate],
        feedbackByCandidateID: [String: XcircuiteRejectedPlanCandidateFeedback],
        globalFeedback: [XcircuiteRejectedPlanGlobalFeedback],
        selectedCandidateID: String,
        runID: String,
        problemID: String,
        strategy: String,
        parameterCandidatesPath: String,
        rejectedPlansPath: String?,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting,
        includeRejectedCandidates: Bool,
        explicitCandidateID: String?,
        explicitRank: Int?
    ) -> XcircuiteParameterCandidateSelectionTrace {
        let scores = selectionScores(
            candidates: candidates,
            feedbackByCandidateID: feedbackByCandidateID,
            globalFeedback: globalFeedback,
            selectedCandidateID: selectedCandidateID,
            feedbackWeighting: feedbackWeighting,
            includeRejectedCandidates: includeRejectedCandidates
        )
        let selectedTotalScore = scores.first(where: { $0.candidateID == selectedCandidateID })?.totalScore ?? 0
        return XcircuiteParameterCandidateSelectionTrace(
            runID: runID,
            problemID: problemID,
            strategy: strategy,
            parameterCandidatesPath: parameterCandidatesPath,
            rejectedPlansPath: rejectedPlansPath,
            feedbackWeighting: feedbackWeighting,
            includeRejectedCandidates: includeRejectedCandidates,
            explicitCandidateID: explicitCandidateID,
            explicitRank: explicitRank,
            selectedCandidateID: selectedCandidateID,
            selectedTotalScore: selectedTotalScore,
            rankedCandidates: scores
        )
    }

    private func selectionScores(
        candidates: [XcircuiteParameterCandidate],
        feedbackByCandidateID: [String: XcircuiteRejectedPlanCandidateFeedback],
        globalFeedback: [XcircuiteRejectedPlanGlobalFeedback],
        selectedCandidateID: String?,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting,
        includeRejectedCandidates: Bool
    ) -> [XcircuiteParameterCandidateSelectionScore] {
        candidates.map { candidate in
            let feedback = feedbackByCandidateID[candidate.candidateID]
            let matchedGlobalFeedback = XcircuiteRejectedPlanGateFeedbackMatcher().matchedCandidateFeedback(
                candidateID: candidate.candidateID,
                verificationGates: candidate.verificationGates,
                globalFeedback: globalFeedback
            )
            let excluded = isExcludedByFeedback(
                feedback,
                includeRejectedCandidates: includeRejectedCandidates
            )
            let candidatePenalty = feedbackPenaltyBreakdown(
                feedback,
                feedbackWeighting: feedbackWeighting,
                includeRejectedCandidates: includeRejectedCandidates
            )
            let globalPenalty = globalFeedbackPenaltyBreakdown(
                matchedGlobalFeedback,
                feedbackWeighting: feedbackWeighting
            )
            let penalty = FeedbackPenaltyBreakdown(
                total: candidatePenalty.total + globalPenalty.total,
                components: candidatePenalty.components + globalPenalty.components
            )
            let selectionState: String
            if excluded {
                selectionState = "excluded"
            } else if candidate.candidateID == selectedCandidateID {
                selectionState = "selected"
            } else {
                selectionState = "eligible"
            }
            return XcircuiteParameterCandidateSelectionScore(
                candidateID: candidate.candidateID,
                rank: candidate.rank,
                baseCost: candidate.normalizedCost,
                feedbackPenalty: penalty.total,
                totalScore: candidate.normalizedCost + penalty.total,
                feedbackPenaltyComponents: penalty.components,
                selectionState: selectionState,
                feedbackStatuses: feedback?.statuses ?? [],
                failedGateIDs: unique((feedback?.failedGateIDs ?? []) + (matchedGlobalFeedback?.failedGateIDs ?? [])),
                diagnosticCodes: unique(
                    (feedback?.diagnosticCodes ?? []) + (matchedGlobalFeedback?.diagnosticCodes ?? [])
                ),
                nextActions: unique((feedback?.nextActions ?? []) + (matchedGlobalFeedback?.nextActions ?? [])),
                exclusionReason: excluded ? "rejected-feedback" : nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.selectionState == "excluded", rhs.selectionState != "excluded" {
                return false
            }
            if lhs.selectionState != "excluded", rhs.selectionState == "excluded" {
                return true
            }
            if lhs.totalScore != rhs.totalScore {
                return lhs.totalScore < rhs.totalScore
            }
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.candidateID < rhs.candidateID
        }
    }

    private func isExcludedByFeedback(
        _ feedback: XcircuiteRejectedPlanCandidateFeedback?,
        includeRejectedCandidates: Bool
    ) -> Bool {
        guard !includeRejectedCandidates else {
            return false
        }
        return feedback?.statuses.contains("rejected") == true
    }

    private func feedbackPenaltyBreakdown(
        _ feedback: XcircuiteRejectedPlanCandidateFeedback?,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting,
        includeRejectedCandidates: Bool
    ) -> FeedbackPenaltyBreakdown {
        guard let feedback else {
            return FeedbackPenaltyBreakdown(total: 0, components: [])
        }
        var components: [XcircuiteParameterCandidateFeedbackPenaltyComponent] = []
        if feedback.statuses.contains("rejected") {
            let value = includeRejectedCandidates
                ? feedbackWeighting.rejectedRetryPenalty
                : feedbackWeighting.rejectedExclusionPenalty
            components.append(XcircuiteParameterCandidateFeedbackPenaltyComponent(
                componentID: includeRejectedCandidates ? "feedback.rejected.retry" : "feedback.rejected.exclusion",
                itemCount: 1,
                unitPenalty: value,
                appliedPenalty: value
            ))
        }
        if feedback.statuses.contains("blocked") {
            components.append(XcircuiteParameterCandidateFeedbackPenaltyComponent(
                componentID: "feedback.blocked",
                itemCount: 1,
                unitPenalty: feedbackWeighting.blockedPenalty,
                appliedPenalty: feedbackWeighting.blockedPenalty
            ))
        }
        components.append(cappedPenaltyComponent(
            componentID: "feedback.failed-gate",
            itemCount: feedback.failedGateIDs.count,
            unitPenalty: feedbackWeighting.failedGatePenaltyPerItem,
            cap: feedbackWeighting.failedGatePenaltyCap
        ))
        components.append(cappedPenaltyComponent(
            componentID: "feedback.diagnostic",
            itemCount: feedback.diagnosticCodes.count,
            unitPenalty: feedbackWeighting.diagnosticPenaltyPerItem,
            cap: feedbackWeighting.diagnosticPenaltyCap
        ))
        components.append(cappedPenaltyComponent(
            componentID: "feedback.next-action",
            itemCount: feedback.nextActions.count,
            unitPenalty: feedbackWeighting.nextActionPenaltyPerItem,
            cap: feedbackWeighting.nextActionPenaltyCap
        ))
        let applied = components.filter { $0.itemCount > 0 || $0.appliedPenalty > 0 }
        return FeedbackPenaltyBreakdown(
            total: applied.map(\.appliedPenalty).reduce(0, +),
            components: applied
        )
    }

    private func globalFeedbackPenaltyBreakdown(
        _ feedback: XcircuiteRejectedPlanCandidateFeedback?,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting
    ) -> FeedbackPenaltyBreakdown {
        guard let feedback else {
            return FeedbackPenaltyBreakdown(total: 0, components: [])
        }
        let components = [
            cappedPenaltyComponent(
                componentID: "feedback.global.failed-gate",
                itemCount: feedback.failedGateIDs.count,
                unitPenalty: feedbackWeighting.failedGatePenaltyPerItem,
                cap: feedbackWeighting.failedGatePenaltyCap
            ),
            cappedPenaltyComponent(
                componentID: "feedback.global.diagnostic",
                itemCount: feedback.diagnosticCodes.count,
                unitPenalty: feedbackWeighting.diagnosticPenaltyPerItem,
                cap: feedbackWeighting.diagnosticPenaltyCap
            ),
            cappedPenaltyComponent(
                componentID: "feedback.global.next-action",
                itemCount: feedback.nextActions.count,
                unitPenalty: feedbackWeighting.nextActionPenaltyPerItem,
                cap: feedbackWeighting.nextActionPenaltyCap
            ),
        ]
        let applied = components.filter { $0.itemCount > 0 || $0.appliedPenalty > 0 }
        return FeedbackPenaltyBreakdown(
            total: applied.map(\.appliedPenalty).reduce(0, +),
            components: applied
        )
    }

    private func cappedPenaltyComponent(
        componentID: String,
        itemCount: Int,
        unitPenalty: Double,
        cap: Double
    ) -> XcircuiteParameterCandidateFeedbackPenaltyComponent {
        let rawPenalty = Double(itemCount) * unitPenalty
        return XcircuiteParameterCandidateFeedbackPenaltyComponent(
            componentID: componentID,
            itemCount: itemCount,
            unitPenalty: unitPenalty,
            cap: cap,
            appliedPenalty: min(rawPenalty, cap)
        )
    }

    private func feedbackWeighting(
        from costModel: XcircuitePlanningCostModel
    ) throws -> XcircuiteParameterCandidateFeedbackWeighting {
        var weighting = XcircuiteParameterCandidateFeedbackWeighting.defaultPolicy()
        var sourceTermIDs: [String] = []
        for term in costModel.terms {
            guard term.weight >= 0, term.weight.isFinite else {
                throw XcircuiteParameterCandidatePlanSynthesisError.invalidFeedbackWeight(
                    termID: term.termID,
                    weight: term.weight
                )
            }
            switch term.termID {
            case "feedback.rejected.exclusion":
                weighting.rejectedExclusionPenalty = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.rejected.retry":
                weighting.rejectedRetryPenalty = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.blocked":
                weighting.blockedPenalty = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.failed-gate":
                weighting.failedGatePenaltyPerItem = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.failed-gate.cap":
                weighting.failedGatePenaltyCap = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.diagnostic":
                weighting.diagnosticPenaltyPerItem = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.diagnostic.cap":
                weighting.diagnosticPenaltyCap = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.next-action":
                weighting.nextActionPenaltyPerItem = term.weight
                sourceTermIDs.append(term.termID)
            case "feedback.next-action.cap":
                weighting.nextActionPenaltyCap = term.weight
                sourceTermIDs.append(term.termID)
            default:
                continue
            }
        }
        if !sourceTermIDs.isEmpty {
            weighting.source = "planning-cost-model"
            weighting.sourceTermIDs = unique(sourceTermIDs)
        }
        return weighting
    }

    private func validateCandidateFeedback(
        _ candidate: XcircuiteParameterCandidate,
        excludedCandidateIDs: Set<String>,
        feedbackSummary: XcircuiteRejectedPlanFeedbackSummary,
        includeRejectedCandidates: Bool
    ) throws {
        guard !includeRejectedCandidates,
              excludedCandidateIDs.contains(candidate.candidateID),
              let feedback = feedbackSummary.candidateFeedback.first(where: {
                  $0.candidateID == candidate.candidateID
              }) else {
            return
        }
        throw XcircuiteParameterCandidatePlanSynthesisError.candidateRejectedByFeedback(
            candidateID: candidate.candidateID,
            statuses: feedback.statuses,
            failedGateIDs: feedback.failedGateIDs
        )
    }

    private func loadRejectedPlanFeedback(
        request: XcircuiteParameterCandidatePlanSynthesisRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> XcircuiteRejectedPlanFeedbackSummary {
        let path = try optionalRejectedPlansPath(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        guard let path else {
            return XcircuiteRejectedPlanFeedbackSummary(
                runID: request.runID,
                rejectedPlansPath: nil,
                recordCount: 0,
                candidateFeedback: [],
                excludedCandidateIDs: []
            )
        }
        let records = try readRejectedPlanRecords(path: path, projectRoot: projectRoot)
        if let mismatched = records.first(where: { $0.runID != request.runID }) {
            throw XcircuiteParameterCandidatePlanSynthesisError.runMismatch(
                expected: request.runID,
                actual: mismatched.runID
            )
        }
        return XcircuiteRejectedPlanFeedbackBuilder().makeFeedbackSummary(
            runID: request.runID,
            path: path,
            records: records
        )
    }

    private func optionalRejectedPlansPath(
        request: XcircuiteParameterCandidatePlanSynthesisRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> String? {
        if let path = request.rejectedPlansPath {
            return try verifiedExplicitPath(
                path,
                artifactID: request.rejectedPlansArtifactID,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot,
                expectedFormat: .text
            ).path
        }
        let artifactID = request.rejectedPlansArtifactID ?? XcircuitePlanningArtifactStore.rejectedPlansArtifactID
        return try verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedFormat: .text,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )?.path
    }

    private func readParameterCandidates(
        path: String,
        projectRoot: URL
    ) throws -> [XcircuiteParameterCandidate] {
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let text = try String(contentsOf: url, encoding: .utf8)
        var candidates: [XcircuiteParameterCandidate] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                candidates.append(try JSONDecoder().decode(XcircuiteParameterCandidate.self, from: data))
            } catch {
                throw XcircuiteParameterCandidatePlanSynthesisError.invalidJSONLine(path: path, line: index + 1)
            }
        }
        return candidates
    }

    private func readRejectedPlanRecords(
        path: String,
        projectRoot: URL
    ) throws -> [XcircuiteRejectedPlanRecord] {
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let text = try String(contentsOf: url, encoding: .utf8)
        var records: [XcircuiteRejectedPlanRecord] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                records.append(try JSONDecoder().decode(XcircuiteRejectedPlanRecord.self, from: data))
            } catch {
                throw XcircuiteParameterCandidatePlanSynthesisError.invalidRejectedPlanJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return records
    }

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL,
        expectedFormat: XcircuiteFileFormat,
        missingError: XcircuiteParameterCandidatePlanSynthesisError
    ) throws -> String {
        if let explicitPath {
            return try verifiedExplicitPath(
                explicitPath,
                artifactID: artifactID,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot,
                expectedFormat: expectedFormat
            ).path
        }
        guard let artifactID else {
            throw missingError
        }
        guard let reference = try verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteParameterCandidatePlanSynthesisError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        return reference.path
    }

    private func verifiedExplicitPath(
        _ explicitPath: String,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL,
        expectedFormat: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let matches = manifest.artifacts.filter { $0.path == explicitPath }
        guard matches.count <= 1 else {
            throw XcircuiteParameterCandidatePlanSynthesisError.invalidArtifactReference(
                path: explicitPath,
                reason: "multiple manifest artifacts reference the same explicit path."
            )
        }
        let reference = try matches.first ?? packageStore.fileReference(
            forProjectRelativePath: explicitPath,
            artifactID: artifactID,
            kind: .other,
            format: expectedFormat,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try validateArtifactReference(
            reference,
            expectedArtifactID: artifactID,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func verifiedManifestArtifactReference(
        artifactID: String,
        expectedFormat: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            return nil
        }
        guard matches.count == 1 else {
            throw XcircuiteParameterCandidatePlanSynthesisError.invalidArtifactReference(
                path: artifactID,
                reason: "run manifest contains \(matches.count) artifacts with the same artifact ID."
            )
        }
        let reference = matches[0]
        try validateArtifactReference(
            reference,
            expectedArtifactID: artifactID,
            expectedFormat: expectedFormat,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func validateArtifactReference(
        _ reference: XcircuiteFileReference,
        expectedArtifactID: String?,
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws {
        if let expectedArtifactID, reference.artifactID != expectedArtifactID {
            throw XcircuiteParameterCandidatePlanSynthesisError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == expectedFormat else {
            throw XcircuiteParameterCandidatePlanSynthesisError.invalidArtifactReference(
                path: reference.path,
                reason: "expected \(expectedFormat.rawValue) artifact, got \(reference.kind.rawValue)/\(reference.format.rawValue)."
            )
        }
        guard reference.producedByRunID == runID else {
            throw XcircuiteParameterCandidatePlanSynthesisError.artifactProducerRunMismatch(
                expected: runID,
                actual: reference.producedByRunID
            )
        }
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteParameterCandidatePlanSynthesisError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
    }

    private func identifier(_ rawValue: String) throws -> String {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar)
                ? String(scalar)
                : "-"
        }
        let collapsed = sanitizedScalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        let value = trimmed.isEmpty ? "parameter-candidate-edit-plan" : trimmed
        try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        return value
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    private struct ParameterCandidateSelection: Sendable, Hashable {
        var candidate: XcircuiteParameterCandidate
        var skippedRejectedCandidateIDs: [String]
        var trace: XcircuiteParameterCandidateSelectionTrace
    }

    private struct FeedbackPenaltyBreakdown: Sendable, Hashable {
        var total: Double
        var components: [XcircuiteParameterCandidateFeedbackPenaltyComponent]
    }

}
