import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteImprovementPlanningArtifactGenerator: Sendable {
    private struct IterationEvidence: Sendable, Hashable {
        var iteration: XcircuiteNumericRepairLoopIteration
        var selectionTrace: XcircuiteParameterCandidateSelectionTrace?
        var verification: XcircuitePlanVerification?
    }

    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
    }

    public func generateImprovementPlanningArtifacts(
        request: XcircuiteImprovementPlanningArtifactGenerationRequest,
        projectRoot: URL
    ) throws -> XcircuiteImprovementPlanningArtifactGenerationResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let loopPath = try requiredPath(
            explicitPath: request.numericRepairLoopPath,
            artifactID: request.numericRepairLoopArtifactID ?? XcircuitePlanningArtifactStore.numericRepairLoopArtifactID,
            manifest: manifest,
            missingError: .missingNumericRepairLoopReference
        )
        let loop = try workspaceStore.readJSON(
            XcircuiteNumericRepairLoopResult.self,
            from: workspaceStore.url(forProjectRelativePath: loopPath, inProjectAt: projectRoot)
        )
        guard loop.runID == request.runID else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.runMismatch(
                expected: request.runID,
                actual: loop.runID
            )
        }
        try validateLoop(loop)

        let problemPath = try optionalPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest
        )
        let problem = try problemPath.map {
            try loadProblem(path: $0, runID: request.runID, loopProblemID: loop.problemID, projectRoot: projectRoot)
        }
        let generatedAt = request.generatedAt ?? ISO8601DateFormatter().string(from: Date())
        let evidence = try loop.iterations.map {
            try iterationEvidence(
                $0,
                runID: request.runID,
                problemID: loop.problemID,
                projectRoot: projectRoot
            )
        }

        let profile = makeThresholdProfile(
            runID: request.runID,
            problem: problem,
            loop: loop,
            loopPath: loopPath,
            generatedAt: generatedAt
        )
        let profileRef = try artifactStore.persistMetricThresholdProfile(
            profile,
            runID: request.runID,
            projectRoot: projectRoot
        )

        let calibration = makeCostCalibrationReport(
            runID: request.runID,
            problemID: problem?.problemID ?? loop.problemID,
            loop: loop,
            loopPath: loopPath,
            evidence: evidence,
            thresholdArtifactID: profileRef.artifactID ?? XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
            generatedAt: generatedAt
        )
        let calibrationRef = try artifactStore.persistCostCalibrationReport(
            calibration,
            runID: request.runID,
            projectRoot: projectRoot
        )

        let paretoSet = try makeParetoCandidateSet(
            runID: request.runID,
            problemID: problem?.problemID ?? loop.problemID,
            loop: loop,
            evidence: evidence,
            thresholdArtifactID: profileRef.artifactID ?? XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
            calibrationArtifactID: calibrationRef.artifactID ?? XcircuitePlanningArtifactStore.costCalibrationArtifactID,
            generatedAt: generatedAt
        )
        let paretoRef = try artifactStore.persistParetoCandidates(
            paretoSet,
            runID: request.runID,
            projectRoot: projectRoot
        )

        let improvementLoop = makeImprovementLoop(
            runID: request.runID,
            problemID: problem?.problemID ?? loop.problemID,
            loop: loop,
            evidence: evidence,
            thresholdArtifactID: profileRef.artifactID ?? XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
            calibrationArtifactID: calibrationRef.artifactID ?? XcircuitePlanningArtifactStore.costCalibrationArtifactID,
            paretoArtifactID: paretoRef.artifactID ?? XcircuitePlanningArtifactStore.paretoCandidatesArtifactID
        )
        let loopRef = try artifactStore.persistImprovementLoop(
            improvementLoop,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let learningReport = try makeRejectedFeedbackLearningReport(
            runID: request.runID,
            problemID: problem?.problemID ?? loop.problemID,
            loopPath: loopPath,
            evidence: evidence,
            generatedAt: generatedAt,
            projectRoot: projectRoot
        )
        let learningRef = try artifactStore.persistRejectedFeedbackLearningReport(
            learningReport,
            runID: request.runID,
            projectRoot: projectRoot
        )

        return XcircuiteImprovementPlanningArtifactGenerationResult(
            status: "generated",
            runID: request.runID,
            problemID: problem?.problemID ?? loop.problemID,
            numericRepairLoopPath: loopPath,
            accepted: loop.accepted,
            iterationCount: loop.iterationCount,
            selectedCandidateID: paretoSet.selectedCandidateID,
            thresholdProfileArtifact: try requireFoundationArtifactReference(
                profileRef,
                field: "metric-threshold-profile"
            ),
            costCalibrationArtifact: try requireFoundationArtifactReference(
                calibrationRef,
                field: "cost-calibration"
            ),
            paretoCandidatesArtifact: try requireFoundationArtifactReference(
                paretoRef,
                field: "pareto-candidates"
            ),
            improvementLoopArtifact: try requireFoundationArtifactReference(
                loopRef,
                field: "improvement-loop"
            ),
            rejectedFeedbackLearningReportArtifact: try requireFoundationArtifactReference(
                learningRef,
                field: "rejected-feedback-learning-report"
            ),
            diagnostics: diagnostics(problem: problem, loop: loop, evidence: evidence)
        )
    }

    private func makeThresholdProfile(
        runID: String,
        problem: XcircuiteCircuitPlanningProblem?,
        loop: XcircuiteNumericRepairLoopResult,
        loopPath: String,
        generatedAt: String
    ) -> XcircuiteMetricThresholdProfile {
        let sourceRefs = problem?.sourceRefs ?? [
            XcircuitePlanningReference(
                refID: "numeric-repair-loop",
                kind: "numeric-repair-loop",
                path: loopPath,
                artifactID: XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
            ),
        ]
        let thresholds = (problem?.objectives ?? []).compactMap { objective -> XcircuiteMetricThresholdProfile.Threshold? in
            guard let targetValue = numberValue(objective.requiredValue) else {
                return nil
            }
            return XcircuiteMetricThresholdProfile.Threshold(
                metricID: objective.objectiveID,
                objectiveID: objective.objectiveID,
                domain: objective.domain,
                metricName: stringValue(objective.evidence["metricName"]) ?? objective.objectiveID,
                direction: thresholdDirection(for: objective),
                targetValue: targetValue,
                tolerance: numberValue(objective.evidence["tolerance"]),
                unit: objective.unit,
                severity: objective.priority,
                sourceRefIDs: objective.sourceRefIDs
            )
        }
        return XcircuiteMetricThresholdProfile(
            runID: runID,
            problemID: problem?.problemID ?? loop.problemID,
            profileID: "\(runID)-metric-threshold-profile",
            generatedAt: generatedAt,
            sourceRefs: sourceRefs,
            thresholds: thresholds,
            policyNotes: thresholds.isEmpty
                ? ["No numeric requiredValue objectives were available for threshold extraction."]
                : ["Thresholds derived from typed planning objectives."]
        )
    }

    private func makeCostCalibrationReport(
        runID: String,
        problemID: String?,
        loop: XcircuiteNumericRepairLoopResult,
        loopPath: String,
        evidence: [IterationEvidence],
        thresholdArtifactID: String,
        generatedAt: String
    ) -> XcircuiteCostCalibrationReport {
        let observations = evidence.compactMap { item -> XcircuiteCostCalibrationReport.Observation? in
            guard let candidateID = item.iteration.selectedCandidateID else {
                return nil
            }
            let selectedScoreFailedGates = item.selectionTrace?.rankedCandidates.first {
                $0.candidateID == candidateID
            }?.failedGateIDs ?? []
            return XcircuiteCostCalibrationReport.Observation(
                candidateID: namespacedCandidateID(iterationIndex: item.iteration.iterationIndex, candidateID: candidateID),
                accepted: item.iteration.accepted,
                selectedTotalScore: item.selectionTrace?.selectedTotalScore,
                failedGateIDs: unique(failedGateIDs(verification: item.verification, iteration: item.iteration) + selectedScoreFailedGates),
                sourceArtifactIDs: sourceArtifactIDs(iteration: item.iteration)
            )
        }
        let failedGateCounts = observations.reduce(into: [String: Int]()) { counts, observation in
            for gateID in observation.failedGateIDs {
                counts[gateID, default: 0] += 1
            }
        }
        let defaultPenalty = evidence
            .compactMap(\.selectionTrace?.feedbackWeighting.failedGatePenaltyPerItem)
            .first ?? XcircuiteParameterCandidateFeedbackWeighting.defaultPolicy().failedGatePenaltyPerItem
        var terms = failedGateCounts
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { gateID, count in
                XcircuiteCostCalibrationReport.Term(
                    termID: "feedback.gate.\(gateID)",
                    gateID: gateID,
                    baseWeight: 1,
                    calibratedWeight: 1 + (Double(count) * defaultPenalty),
                    evidenceCount: count,
                    rationale: "Derived from failed verification gates observed in numeric repair loop outcomes."
                )
            }
        if terms.isEmpty {
            terms.append(XcircuiteCostCalibrationReport.Term(
                termID: "feedback.loop.acceptance",
                baseWeight: 1,
                calibratedWeight: loop.accepted ? 1 : 1 + defaultPenalty,
                evidenceCount: max(loop.iterationCount, 1),
                rationale: "Derived from numeric repair loop acceptance status when no failed gate terms were present."
            ))
        }
        return XcircuiteCostCalibrationReport(
            runID: runID,
            problemID: problemID,
            calibrationID: "\(runID)-cost-calibration",
            generatedAt: generatedAt,
            thresholdProfileArtifactID: thresholdArtifactID,
            inputArtifactIDs: unique([
                XcircuitePlanningArtifactStore.numericRepairLoopArtifactID,
                "path:\(loopPath)",
            ] + evidence.flatMap { sourceArtifactIDs(iteration: $0.iteration) }),
            calibratedTerms: terms,
            observations: observations,
            diagnostics: observations.isEmpty ? ["No selected candidate observations were available."] : []
        )
    }

    private func makeParetoCandidateSet(
        runID: String,
        problemID: String?,
        loop: XcircuiteNumericRepairLoopResult,
        evidence: [IterationEvidence],
        thresholdArtifactID: String,
        calibrationArtifactID: String,
        generatedAt: String
    ) throws -> XcircuiteParetoCandidateSet {
        let candidates = try evidence.flatMap { item -> [XcircuiteParetoCandidateSet.Candidate] in
            guard let trace = item.selectionTrace else {
                return []
            }
            let maxScore = max(trace.rankedCandidates.map(\.totalScore).max() ?? 0, 1)
            let sortedScores = trace.rankedCandidates.sorted { lhs, rhs in
                if lhs.totalScore != rhs.totalScore {
                    return lhs.totalScore < rhs.totalScore
                }
                return lhs.candidateID < rhs.candidateID
            }
            var strongerCandidateIDs: [String] = []
            return try sortedScores.map { score in
                let candidateID = namespacedCandidateID(
                    iterationIndex: item.iteration.iterationIndex,
                    candidateID: score.candidateID
                )
                let gateStatuses = gateStatuses(
                    score: score,
                    verification: item.iteration.selectedCandidateID == score.candidateID ? item.verification : nil
                )
                let candidate = try XcircuiteParetoCandidateSet.Candidate(
                    runID: runID,
                    problemID: problemID,
                    generatedAt: generatedAt,
                    candidateID: candidateID,
                    sourceCandidateID: score.candidateID,
                    frontierRank: score.rank,
                    dominatedByCandidateIDs: strongerCandidateIDs,
                    metrics: [
                        try XcircuiteParetoCandidateSet.Metric(
                            metricID: "selection-total-score",
                            value: score.totalScore,
                            normalizedValue: score.totalScore / maxScore,
                            direction: "minimize"
                        ),
                        try XcircuiteParetoCandidateSet.Metric(
                            metricID: "selection-base-cost",
                            value: score.baseCost,
                            normalizedValue: score.baseCost / maxScore,
                            direction: "minimize"
                        ),
                        try XcircuiteParetoCandidateSet.Metric(
                            metricID: "selection-feedback-penalty",
                            value: score.feedbackPenalty,
                            normalizedValue: score.feedbackPenalty / maxScore,
                            direction: "minimize"
                        ),
                    ],
                    gateStatuses: gateStatuses,
                    rationale: "Projected from numeric repair loop selection score \(score.totalScore)."
                )
                strongerCandidateIDs.append(candidateID)
                return candidate
            }
        }
        return try XcircuiteParetoCandidateSet(
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            thresholdProfileArtifactID: thresholdArtifactID,
            costCalibrationArtifactID: calibrationArtifactID,
            sourceCandidateArtifactIDs: unique(evidence.compactMap(\.iteration.parameterCandidatesArtifact?.artifactID)),
            candidates: candidates,
            selectedCandidateID: loop.acceptedIterationIndex.flatMap { acceptedIndex in
                loop.selectedCandidateID.map {
                    namespacedCandidateID(iterationIndex: acceptedIndex, candidateID: $0)
                }
            }
        )
    }

    private func makeImprovementLoop(
        runID: String,
        problemID: String?,
        loop: XcircuiteNumericRepairLoopResult,
        evidence: [IterationEvidence],
        thresholdArtifactID: String,
        calibrationArtifactID: String,
        paretoArtifactID: String
    ) -> XcircuiteImprovementLoopResult {
        XcircuiteImprovementLoopResult(
            runID: runID,
            problemID: problemID,
            loopID: "\(runID)-improvement-loop",
            status: loop.status,
            thresholdProfileArtifactID: thresholdArtifactID,
            costCalibrationArtifactID: calibrationArtifactID,
            paretoCandidateArtifactID: paretoArtifactID,
            iterationCount: loop.iterationCount,
            acceptedCandidateID: loop.acceptedIterationIndex.flatMap { acceptedIndex in
                loop.selectedCandidateID.map {
                    namespacedCandidateID(iterationIndex: acceptedIndex, candidateID: $0)
                }
            },
            iterations: evidence.map { item in
                let selectedScoreFailedGates = item.iteration.selectedCandidateID.flatMap { candidateID in
                    item.selectionTrace?.rankedCandidates.first {
                        $0.candidateID == candidateID
                    }?.failedGateIDs
                } ?? []
                return XcircuiteImprovementLoopResult.Iteration(
                    iterationIndex: item.iteration.iterationIndex,
                    status: item.iteration.status,
                    selectedCandidateID: item.iteration.selectedCandidateID.map {
                        namespacedCandidateID(iterationIndex: item.iteration.iterationIndex, candidateID: $0)
                    },
                    accepted: item.iteration.accepted,
                    producedArtifactIDs: sourceArtifactIDs(iteration: item.iteration),
                    failedGateIDs: unique(failedGateIDs(verification: item.verification, iteration: item.iteration) + selectedScoreFailedGates)
                )
            },
            diagnostics: loop.diagnostics.map(\.code),
            nextActions: loop.nextActions
        )
    }

    private func makeRejectedFeedbackLearningReport(
        runID: String,
        problemID: String?,
        loopPath: String,
        evidence: [IterationEvidence],
        generatedAt: String,
        projectRoot: URL
    ) throws -> XcircuiteRejectedFeedbackLearningReport {
        let rejectedPlanPaths = unique(evidence.flatMap { item in
            [
                item.selectionTrace?.rejectedPlansPath,
                item.iteration.rejectedPlansArtifact?.path,
            ].compactMap { $0 }
        })
        let rejectedRecords = try loadRejectedPlanRecords(paths: rejectedPlanPaths, projectRoot: projectRoot)
        let retainedFailedGateIDs = unique(rejectedRecords.flatMap(\.failedGateIDs))
        let retainedDiagnosticCodes = unique(rejectedRecords.flatMap { record in
            record.diagnostics.map(\.code)
        })
        let impacts = try evidence.flatMap { item -> [XcircuiteRejectedFeedbackLearningReport.FeedbackImpact] in
            guard let trace = item.selectionTrace else {
                return []
            }
            let feedbackFreeRanks = feedbackFreeRanks(in: trace.rankedCandidates)
            return try trace.rankedCandidates.compactMap { score in
                let sourceRecords = sourceRejectionRecords(
                    for: score,
                    rejectedRecords: rejectedRecords
                )
                guard score.feedbackPenalty > 0
                    || !score.feedbackPenaltyComponents.isEmpty
                    || !score.feedbackStatuses.isEmpty
                    || !sourceRecords.isEmpty else {
                    return nil
                }
                let feedbackFreeRank = feedbackFreeRanks[score.candidateID] ?? score.rank
                return try XcircuiteRejectedFeedbackLearningReport.FeedbackImpact(
                    iterationIndex: item.iteration.iterationIndex,
                    candidateID: score.candidateID,
                    feedbackFreeRank: feedbackFreeRank,
                    feedbackAwareRank: score.rank,
                    rankDelta: score.rank - feedbackFreeRank,
                    baseCost: score.baseCost,
                    feedbackPenalty: score.feedbackPenalty,
                    totalScore: score.totalScore,
                    feedbackStatuses: score.feedbackStatuses,
                    failedGateIDs: score.failedGateIDs,
                    diagnosticCodes: score.diagnosticCodes,
                    penaltyComponents: score.feedbackPenaltyComponents,
                    sourceRejectionIDs: unique(sourceRecords.map(\.rejectionID)),
                    sourcePlanIDs: unique(sourceRecords.map(\.planID))
                )
            }
        }
        let diagnostics = learningDiagnostics(
            rejectedPlanPaths: rejectedPlanPaths,
            rejectedRecords: rejectedRecords,
            evidence: evidence,
            impacts: impacts
        )
        return try XcircuiteRejectedFeedbackLearningReport(
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            numericRepairLoopPath: loopPath,
            rejectedPlansPath: rejectedPlanPaths.first,
            rejectedRecordCount: rejectedRecords.count,
            selectionTraceArtifactIDs: unique(evidence.compactMap(\.iteration.selectionTraceArtifact?.artifactID)),
            impactedCandidateCount: impacts.count,
            penalizedCandidateCount: impacts.filter { $0.feedbackPenalty > 0 }.count,
            rankChangedCandidateCount: impacts.filter { $0.rankDelta != 0 }.count,
            scoreDeltaCandidateCount: impacts.filter { $0.feedbackPenalty > 0 || !$0.penaltyComponents.isEmpty }.count,
            retainedFailedGateIDs: retainedFailedGateIDs,
            retainedDiagnosticCodes: retainedDiagnosticCodes,
            feedbackImpacts: impacts,
            diagnostics: diagnostics
        )
    }

    private func loadRejectedPlanRecords(
        paths: [String],
        projectRoot: URL
    ) throws -> [XcircuiteRejectedPlanRecord] {
        var records: [XcircuiteRejectedPlanRecord] = []
        let decoder = JSONDecoder()
        for path in paths {
            let url = try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") {
                records.append(try decoder.decode(XcircuiteRejectedPlanRecord.self, from: Data(line.utf8)))
            }
        }
        return records
    }

    private func feedbackFreeRanks(
        in scores: [XcircuiteParameterCandidateSelectionScore]
    ) -> [String: Int] {
        var ranks: [String: Int] = [:]
        for (offset, score) in scores
            .sorted(by: { lhs, rhs in
                if lhs.baseCost != rhs.baseCost {
                    return lhs.baseCost < rhs.baseCost
                }
                return lhs.candidateID < rhs.candidateID
            }
            )
            .enumerated()
        {
            if ranks[score.candidateID] == nil {
                ranks[score.candidateID] = offset + 1
            }
        }
        return ranks
    }

    private func sourceRejectionRecords(
        for score: XcircuiteParameterCandidateSelectionScore,
        rejectedRecords: [XcircuiteRejectedPlanRecord]
    ) -> [XcircuiteRejectedPlanRecord] {
        rejectedRecords.filter { record in
            record.sourceParameterCandidateIDs.contains(score.candidateID)
                || !Set(record.failedGateIDs).intersection(score.failedGateIDs).isEmpty
                || !Set(record.diagnostics.map(\.code)).intersection(score.diagnosticCodes).isEmpty
        }
    }

    private func learningDiagnostics(
        rejectedPlanPaths: [String],
        rejectedRecords: [XcircuiteRejectedPlanRecord],
        evidence: [IterationEvidence],
        impacts: [XcircuiteRejectedFeedbackLearningReport.FeedbackImpact]
    ) -> [String] {
        var diagnostics: [String] = []
        if rejectedPlanPaths.isEmpty {
            diagnostics.append("no rejected feedback source path was available")
        }
        if rejectedRecords.isEmpty {
            diagnostics.append("no rejected feedback records were available")
        }
        if evidence.allSatisfy({ $0.selectionTrace == nil }) {
            diagnostics.append("no selection trace was available for rank-change analysis")
        }
        if impacts.isEmpty {
            diagnostics.append("no feedback-impacted candidates were observed")
        }
        if !impacts.isEmpty, impacts.allSatisfy({ $0.rankDelta == 0 }) {
            diagnostics.append("feedback penalties were observed but candidate ranks did not change")
        }
        return diagnostics
    }

    private func iterationEvidence(
        _ iteration: XcircuiteNumericRepairLoopIteration,
        runID: String,
        problemID: String?,
        projectRoot: URL
    ) throws -> IterationEvidence {
        let selectionTrace = try optionalJSON(
            XcircuiteParameterCandidateSelectionTrace.self,
                from: archivedReference(
                    role: "selection-trace",
                    iteration: iteration
                ) ?? iteration.selectionTraceArtifact,
            projectRoot: projectRoot
        )
        if let selectionTrace {
            try validateSelectionTrace(
                selectionTrace,
                iteration: iteration,
                runID: runID,
                problemID: problemID
            )
        }
        let verification = try optionalJSON(
            XcircuitePlanVerification.self,
                from: archivedReference(
                    role: "plan-verification",
                    iteration: iteration
                ) ?? iteration.planVerificationArtifact,
            projectRoot: projectRoot
        )
        if let verification {
            try validateVerification(
                verification,
                iteration: iteration,
                runID: runID,
                problemID: problemID
            )
        }
        return IterationEvidence(
            iteration: iteration,
            selectionTrace: selectionTrace,
            verification: verification
        )
    }

    private func archivedReference(
        role: String,
        iteration: XcircuiteNumericRepairLoopIteration
    ) -> ArtifactReference? {
        iteration.archivedArtifactRefs.first {
            $0.id.rawValue == "planning-numeric-repair-loop-iteration-\(iteration.iterationIndex)-\(role)"
        }
    }

    private func optionalJSON<T: Decodable>(
        _ type: T.Type,
        from reference: ArtifactReference?,
        projectRoot: URL
    ) throws -> T? {
        guard let reference else {
            return nil
        }
        return try workspaceStore.readJSON(
            T.self,
            from: try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        )
    }

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try workspaceStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    private func loadProblem(
        path: String,
        runID: String,
        loopProblemID: String?,
        projectRoot: URL
    ) throws -> XcircuiteCircuitPlanningProblem {
        let problem = try workspaceStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        )
        guard problem.runID == runID else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.runMismatch(
                expected: runID,
                actual: problem.runID
            )
        }
        if let loopProblemID, loopProblemID != problem.problemID {
            throw XcircuiteImprovementPlanningArtifactGenerationError.problemMismatch(
                expected: loopProblemID,
                actual: problem.problemID
            )
        }
        return problem
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String,
        manifest: XcircuiteRunManifest,
        missingError: XcircuiteImprovementPlanningArtifactGenerationError
    ) throws -> String {
        if let explicitPath {
            return explicitPath
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw missingError
        }
        guard matches.count == 1 else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.duplicateManifestArtifact(
                artifactID: artifactID,
                paths: matches.map(\.path).sorted()
            )
        }
        return matches[0].path
    }

    private func optionalPath(
        explicitPath: String?,
        artifactID: String,
        manifest: XcircuiteRunManifest
    ) throws -> String? {
        if let explicitPath {
            return explicitPath
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard matches.count <= 1 else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.duplicateManifestArtifact(
                artifactID: artifactID,
                paths: matches.map(\.path).sorted()
            )
        }
        return matches.first?.path
    }

    private func validateLoop(_ loop: XcircuiteNumericRepairLoopResult) throws {
        guard loop.iterationCount == loop.iterations.count else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.loopIterationCountMismatch(
                reported: loop.iterationCount,
                actual: loop.iterations.count
            )
        }
        if let duplicateIndex = firstDuplicate(loop.iterations.map(\.iterationIndex)) {
            throw XcircuiteImprovementPlanningArtifactGenerationError.duplicateIterationIndex(duplicateIndex)
        }
        if let acceptedIterationIndex = loop.acceptedIterationIndex,
           !loop.iterations.contains(where: { $0.iterationIndex == acceptedIterationIndex }) {
            throw XcircuiteImprovementPlanningArtifactGenerationError.acceptedIterationMissing(acceptedIterationIndex)
        }
    }

    private func validateSelectionTrace(
        _ trace: XcircuiteParameterCandidateSelectionTrace,
        iteration: XcircuiteNumericRepairLoopIteration,
        runID: String,
        problemID: String?
    ) throws {
        guard trace.runID == runID else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.runMismatch(
                expected: runID,
                actual: trace.runID
            )
        }
        if let problemID, trace.problemID != problemID {
            throw XcircuiteImprovementPlanningArtifactGenerationError.problemMismatch(
                expected: problemID,
                actual: trace.problemID
            )
        }
        if let duplicateCandidateID = firstDuplicate(trace.rankedCandidates.map(\.candidateID)) {
            throw XcircuiteImprovementPlanningArtifactGenerationError.duplicateSelectionCandidateID(
                iterationIndex: iteration.iterationIndex,
                candidateID: duplicateCandidateID
            )
        }
        let selectedCandidateID = iteration.selectedCandidateID ?? trace.selectedCandidateID
        if let iterationCandidateID = iteration.selectedCandidateID,
           trace.selectedCandidateID != iterationCandidateID {
            throw XcircuiteImprovementPlanningArtifactGenerationError.selectedCandidateMismatch(
                iterationIndex: iteration.iterationIndex,
                expected: iterationCandidateID,
                actual: trace.selectedCandidateID
            )
        }
        guard trace.rankedCandidates.contains(where: { $0.candidateID == selectedCandidateID }) else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.selectedCandidateMissing(
                iterationIndex: iteration.iterationIndex,
                candidateID: selectedCandidateID
            )
        }
    }

    private func validateVerification(
        _ verification: XcircuitePlanVerification,
        iteration: XcircuiteNumericRepairLoopIteration,
        runID: String,
        problemID: String?
    ) throws {
        guard verification.runID == runID else {
            throw XcircuiteImprovementPlanningArtifactGenerationError.runMismatch(
                expected: runID,
                actual: verification.runID
            )
        }
        if let problemID, verification.problemID != problemID {
            throw XcircuiteImprovementPlanningArtifactGenerationError.problemMismatch(
                expected: problemID,
                actual: verification.problemID
            )
        }
        if let planID = iteration.planID, verification.planID != planID {
            throw XcircuiteImprovementPlanningArtifactGenerationError.planMismatch(
                expected: planID,
                actual: verification.planID
            )
        }
        if let duplicateGateID = firstDuplicate(verification.gateResults.map(\.gateID)) {
            throw XcircuiteImprovementPlanningArtifactGenerationError.duplicateVerificationGateID(
                iterationIndex: iteration.iterationIndex,
                gateID: duplicateGateID
            )
        }
    }

    private func failedGateIDs(
        verification: XcircuitePlanVerification?,
        iteration: XcircuiteNumericRepairLoopIteration
    ) -> [String] {
        let gateFailures = verification?.gateResults.compactMap { gate in
            gate.status == "passed" ? nil : gate.gateID
        } ?? []
        if !gateFailures.isEmpty {
            return unique(gateFailures)
        }
        return iteration.diagnostics.compactMap { diagnostic in
            diagnostic.code.hasPrefix("gate:")
                ? String(diagnostic.code.dropFirst("gate:".count))
                : nil
        }
    }

    private func gateStatuses(
        score: XcircuiteParameterCandidateSelectionScore,
        verification: XcircuitePlanVerification?
    ) -> [String: String] {
        var statuses: [String: String] = [:]
        for gateID in score.failedGateIDs {
            statuses[gateID] = "failed"
        }
        for gate in verification?.gateResults ?? [] {
            statuses[gate.gateID] = gate.status
        }
        return statuses
    }

    private func sourceArtifactIDs(iteration: XcircuiteNumericRepairLoopIteration) -> [String] {
        let directArtifactIDs = [
            iteration.parameterCandidatesArtifact?.artifactID,
            iteration.searchTraceArtifact?.artifactID,
            iteration.selectionTraceArtifact?.artifactID,
            iteration.candidatePlanArtifact?.artifactID,
            iteration.planExecutionArtifact?.artifactID,
            iteration.designDiffArtifact?.artifactID,
            iteration.planVerificationArtifact?.artifactID,
            iteration.rejectedPlansArtifact?.artifactID,
        ].compactMap { $0 }
        let producedArtifactIDs = iteration.producedArtifacts.compactMap(\.artifactID)
        let archivedArtifactIDs = iteration.archivedArtifactRefs.compactMap(\.artifactID)
        return unique(directArtifactIDs + producedArtifactIDs + archivedArtifactIDs)
    }

    private func namespacedCandidateID(iterationIndex: Int, candidateID: String) -> String {
        "iteration-\(iterationIndex)-\(candidateID)"
    }

    private func thresholdDirection(for objective: XcircuitePlanningObjective) -> String {
        let target = objective.target.lowercased()
        let kind = objective.kind.lowercased()
        if kind.contains("reduce") || target.contains("below") || target.contains("at-most") {
            return "at-most"
        }
        if kind.contains("increase") || target.contains("above") || target.contains("at-least") {
            return "at-least"
        }
        return "within-tolerance"
    }

    private func numberValue(_ value: XcircuiteJSONValue?) -> Double? {
        guard let value else {
            return nil
        }
        if case .number(let number) = value {
            return number
        }
        return nil
    }

    private func stringValue(_ value: XcircuiteJSONValue?) -> String? {
        guard let value else {
            return nil
        }
        if case .string(let string) = value {
            return string
        }
        return nil
    }

    private func diagnostics(
        problem: XcircuiteCircuitPlanningProblem?,
        loop: XcircuiteNumericRepairLoopResult,
        evidence: [IterationEvidence]
    ) -> [String] {
        var diagnostics: [String] = []
        if problem == nil {
            diagnostics.append("planning problem artifact was not available; threshold profile uses loop provenance only")
        }
        if evidence.allSatisfy({ $0.selectionTrace == nil }) {
            diagnostics.append("selection trace artifacts were not available; Pareto candidate set may be empty")
        }
        if !loop.accepted {
            diagnostics.append("numeric repair loop did not reach an accepted candidate")
        }
        return diagnostics
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private func firstDuplicate<T: Hashable>(_ values: [T]) -> T? {
        var seen: Set<T> = []
        for value in values where !seen.insert(value).inserted {
            return value
        }
        return nil
    }
}
