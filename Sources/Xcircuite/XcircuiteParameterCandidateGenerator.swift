import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteParameterCandidateGenerator: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let makeArtifactReferenceVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        makeArtifactReferenceVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.makeArtifactReferenceVerifier = makeArtifactReferenceVerifier
    }

    public func generateParameterCandidates(
        request: XcircuiteParameterCandidateGenerationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteParameterCandidateGenerationResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.maxCandidates > 0 else {
            throw XcircuiteParameterCandidateGenerationError.invalidMaxCandidates(request.maxCandidates)
        }
        let manifest = try await loadRunManifest(runID: request.runID)
        let problemPath = try await requiredPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .json
        )
        let problem = try await workspaceStore.readJSON(XcircuiteCircuitPlanningProblem.self, from: problemPath)
        guard problem.runID == request.runID else {
            throw XcircuiteParameterCandidateGenerationError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }
        let feedbackContext = try await loadFeedbackLearningContext(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        let calibrationContext = try await loadCalibrationContext(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )

        let generated = makeParameterCandidates(
            problem: problem,
            strategy: request.strategy,
            maxCandidates: request.maxCandidates,
            problemPath: problemPath,
            feedbackContext: feedbackContext,
            calibrationContext: calibrationContext
        )
        let reference: ArtifactReference?
        if generated.candidates.isEmpty {
            reference = nil
        } else {
            reference = try await artifactStore.persistParameterCandidates(
                generated.candidates,
                runID: request.runID,
                projectRoot: projectRoot
            )
        }
        let searchTraceReference = try await artifactStore.persistParameterCandidateSearchTrace(
            generated.searchTrace,
            runID: request.runID,
            projectRoot: projectRoot
        )

        return XcircuiteParameterCandidateGenerationResult(
            status: generated.candidates.isEmpty ? "blocked" : "generated",
            runID: request.runID,
            problemID: problem.problemID,
            strategy: request.strategy,
            candidateCount: generated.candidates.count,
            problemPath: problemPath,
            parameterCandidatesArtifact: reference,
            searchTrace: generated.searchTrace,
            searchTraceArtifact: searchTraceReference,
            diagnostics: generated.diagnostics
        )
    }

    public func makeParameterCandidates(
        problem: XcircuiteCircuitPlanningProblem,
        strategy: String = "bounded-midpoint-sweep",
        maxCandidates: Int = 9,
        problemPath: String? = nil
    ) -> ParameterCandidateGeneration {
        makeParameterCandidates(
            problem: problem,
            strategy: strategy,
            maxCandidates: maxCandidates,
            problemPath: problemPath,
            feedbackContext: nil,
            calibrationContext: nil
        )
    }

    private func makeParameterCandidates(
        problem: XcircuiteCircuitPlanningProblem,
        strategy: String,
        maxCandidates: Int,
        problemPath: String?,
        feedbackContext: FeedbackLearningContext?,
        calibrationContext: CalibrationContext?
    ) -> ParameterCandidateGeneration {
        var diagnostics: [XcircuiteParameterCandidateDiagnostic] = []
        var candidates: [CandidateDraft] = []
        var actionTraces: [XcircuiteParameterCandidateSearchActionTrace] = []
        let learningEnabled = feedbackLearningEnabled(strategy)
        for action in problem.candidateActions.sorted(by: { $0.actionID < $1.actionID }) {
            let bounds = parameterBounds(from: action, diagnostics: &diagnostics)
            guard !bounds.isEmpty else {
                continue
            }
            let generatedDrafts = candidateDrafts(
                action: action,
                bounds: bounds,
                problem: problem,
                strategy: strategy,
                feedbackContext: feedbackContext,
                calibrationContext: calibrationContext,
                learningEnabled: learningEnabled
            )
            candidates.append(contentsOf: generatedDrafts.drafts)
            actionTraces.append(generatedDrafts.actionTrace)
        }

        let limitedDrafts = Array(candidates
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                if lhs.normalizedCost != rhs.normalizedCost {
                    return lhs.normalizedCost < rhs.normalizedCost
                }
                return lhs.sortKey < rhs.sortKey
            }
            .prefix(maxCandidates))
        let limited = limitedDrafts
            .enumerated()
            .map { index, draft in
                XcircuiteParameterCandidate(
                    candidateID: candidateID(problemID: problem.problemID, draft: draft),
                    runID: problem.runID,
                    problemID: problem.problemID,
                    rank: index + 1,
                    sourceActionID: draft.sourceActionID,
                    sourceOperationID: draft.sourceOperationID,
                    sourceObjectiveIDs: draft.sourceObjectiveIDs,
                    assignments: draft.assignments,
                    normalizedCost: draft.normalizedCost,
                    verificationGates: draft.verificationGates,
                    rationale: draft.rationale,
                    diagnostics: draft.diagnostics
                )
            }

        if limited.isEmpty {
            diagnostics.append(XcircuiteParameterCandidateDiagnostic(
                severity: "warning",
                code: "no-bounded-parameter-actions",
                message: "No candidate action declared parameterBounds for bounded numeric search."
            ))
        }
        let searchTrace = XcircuiteParameterCandidateSearchTrace(
            runID: problem.runID,
            problemID: problem.problemID,
            strategy: strategy,
            maxCandidates: maxCandidates,
            problemPath: problemPath,
            generatedCandidateCount: limited.count,
            generatedCandidateIDs: limited.map(\.candidateID),
            actionTraces: actionTraces,
            feedbackTrace: feedbackContext?.trace(strategy: strategy),
            calibrationTrace: calibrationContext?.trace(
                strategy: strategy,
                appliedDrafts: limitedDrafts.filter { $0.calibrationAdjustment.adjustment != 0 }
            ),
            diagnostics: diagnostics
        )
        return ParameterCandidateGeneration(
            candidates: Array(limited),
            searchTrace: searchTrace,
            diagnostics: diagnostics
        )
    }

    private func candidateDrafts(
        action: XcircuitePlanningCandidateAction,
        bounds: [XcircuiteParameterBound],
        problem: XcircuiteCircuitPlanningProblem,
        strategy: String,
        feedbackContext: FeedbackLearningContext?,
        calibrationContext: CalibrationContext?,
        learningEnabled: Bool
    ) -> CandidateDraftGeneration {
        let baseAssignments = bounds.map {
            XcircuiteParameterAssignment(
                name: $0.name,
                value: nominalValue(for: $0),
                unit: $0.unit
            )
        }
        let baseFeedback = learningEnabled
            ? feedback(for: baseAssignments, context: feedbackContext)
            : nil
        let baseCalibration = calibrationAdjustment(
            action: action,
            assignments: baseAssignments,
            problemID: problem.problemID,
            context: calibrationContext
        )
        var drafts: [CandidateDraft] = [
            CandidateDraft(
                sourceActionID: action.actionID,
                sourceOperationID: action.operationID,
                sourceObjectiveIDs: action.sourceObjectiveIDs,
                assignments: baseAssignments,
                normalizedCost: 0,
                priority: (baseFeedback?.penalty ?? 0) + baseCalibration.adjustment,
                verificationGates: action.verificationGates,
                rationale: rationale(
                    base: "Base \(strategy) candidate for \(action.operationID).",
                    feedback: baseFeedback,
                    calibration: baseCalibration
                ),
                diagnostics: feedbackDiagnostics(
                    feedback: baseFeedback,
                    actionID: action.actionID
                ) + calibrationDiagnostics(
                    calibration: baseCalibration,
                    actionID: action.actionID
                ),
                calibrationAdjustment: baseCalibration,
                sortKey: "\(action.actionID):base"
            ),
        ]
        var parameterTraces: [XcircuiteParameterCandidateSearchParameterTrace] = []
        for bound in bounds.sorted(by: { $0.name < $1.name }) {
            let valueDrafts = searchValueDrafts(for: bound, strategy: strategy)
            parameterTraces.append(searchParameterTrace(
                bound: bound,
                values: valueDrafts,
                feedbackContext: feedbackContext
            ))
            for valueDraft in valueDrafts {
                let value = valueDraft.value
                guard value != nominalValue(for: bound) else {
                    continue
                }
                let assignments = baseAssignments.map { assignment in
                    assignment.name == bound.name
                        ? XcircuiteParameterAssignment(
                            name: assignment.name,
                            value: value,
                            unit: assignment.unit
                        )
                        : assignment
                }
                let candidateFeedback = learningEnabled
                    ? feedback(for: assignments, context: feedbackContext)
                    : nil
                let candidateCalibration = calibrationAdjustment(
                    action: action,
                    assignments: assignments,
                    problemID: problem.problemID,
                    context: calibrationContext
                )
                let diagnostics = valueDraft.diagnosticCode.map {
                    [XcircuiteParameterCandidateDiagnostic(
                        severity: "info",
                        code: $0,
                        message: "Generated \(bound.name)=\(value) using \(strategy).",
                        actionID: action.actionID
                    )]
                } ?? []
                drafts.append(CandidateDraft(
                    sourceActionID: action.actionID,
                    sourceOperationID: action.operationID,
                    sourceObjectiveIDs: action.sourceObjectiveIDs,
                    assignments: assignments,
                    normalizedCost: normalizedCost(assignments: assignments, bounds: bounds),
                    priority: valueDraft.priority
                        + (candidateFeedback?.penalty ?? 0)
                        + candidateCalibration.adjustment,
                    verificationGates: action.verificationGates,
                    rationale: rationale(
                        base: "\(valueDraft.source) \(bound.name) within declared bounds for \(action.operationID).",
                        feedback: candidateFeedback,
                        calibration: candidateCalibration
                    ),
                    diagnostics: diagnostics + feedbackDiagnostics(
                        feedback: candidateFeedback,
                        actionID: action.actionID
                    ) + calibrationDiagnostics(
                        calibration: candidateCalibration,
                        actionID: action.actionID
                    ),
                    calibrationAdjustment: candidateCalibration,
                    sortKey: "\(action.actionID):\(bound.name):\(valueDraft.priority):\(value)"
                ))
            }
        }
        return CandidateDraftGeneration(
            drafts: deduplicate(drafts),
            actionTrace: XcircuiteParameterCandidateSearchActionTrace(
                actionID: action.actionID,
                operationID: action.operationID,
                sourceObjectiveIDs: action.sourceObjectiveIDs,
                parameterTraces: parameterTraces
            )
        )
    }

    private func deduplicate(_ drafts: [CandidateDraft]) -> [CandidateDraft] {
        var seen: Set<String> = []
        var unique: [CandidateDraft] = []
        for draft in drafts {
            let key = draft.assignments
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: ";")
            if seen.insert(key).inserted {
                unique.append(draft)
            }
        }
        return unique
    }

    private func parameterBounds(
        from action: XcircuitePlanningCandidateAction,
        diagnostics: inout [XcircuiteParameterCandidateDiagnostic]
    ) -> [XcircuiteParameterBound] {
        guard let rawBounds = action.parameterHints["parameterBounds"]
            ?? action.parameterHints["bounds"]
        else {
            return []
        }
        guard case .parameterBounds(let boundValues) = rawBounds else {
            diagnostics.append(invalidBoundsDiagnostic(
                actionID: action.actionID,
                message: "parameterBounds must be an array of objects."
            ))
            return []
        }
        var bounds: [XcircuiteParameterBound] = []
        for bound in boundValues {
            guard let bound = validatedParameterBound(
                bound,
                actionID: action.actionID,
                diagnostics: &diagnostics
            ) else {
                continue
            }
            bounds.append(bound)
        }
        return bounds
    }

    private func validatedParameterBound(
        _ bound: XcircuiteParameterBound,
        actionID: String,
        diagnostics: inout [XcircuiteParameterCandidateDiagnostic]
    ) -> XcircuiteParameterBound? {
        let name = bound.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            diagnostics.append(invalidBoundsDiagnostic(
                actionID: actionID,
                message: "Parameter bound is missing a name."
            ))
            return nil
        }
        guard bound.lowerBound.isFinite, bound.upperBound.isFinite else {
            diagnostics.append(invalidBoundsDiagnostic(
                actionID: actionID,
                message: "Parameter bound \(name) is missing lower or upper numeric bounds."
            ))
            return nil
        }
        guard bound.lowerBound <= bound.upperBound else {
            diagnostics.append(invalidBoundsDiagnostic(
                actionID: actionID,
                message: "Parameter bound \(name) has lowerBound greater than upperBound."
            ))
            return nil
        }
        return bound
    }

    private func nominalValue(for bound: XcircuiteParameterBound) -> Double {
        if let nominal = bound.nominalValue,
           nominal >= bound.lowerBound,
           nominal <= bound.upperBound {
            return snapped(nominal, for: bound)
        }
        return snapped((bound.lowerBound + bound.upperBound) / 2, for: bound)
    }

    private func edgeValues(for bound: XcircuiteParameterBound) -> [Double] {
        let values = [
            bound.lowerBound,
            bound.upperBound,
        ].map { snapped($0, for: bound) }
        return unique(values)
    }

    private func searchValueDrafts(
        for bound: XcircuiteParameterBound,
        strategy: String
    ) -> [SearchValueDraft] {
        if strategy == "adaptive-bounded-refinement"
            || strategy == "feedback-aware-bounded-refinement"
            || strategy == "calibrated-feedback-aware-bounded-refinement" {
            return adaptiveValueDrafts(for: bound)
        }
        return edgeValues(for: bound).map { value in
            SearchValueDraft(
                value: value,
                priority: normalizedDistance(value: value, for: bound),
                source: "Sweep",
                diagnosticCode: nil
            )
        }
    }

    private func adaptiveValueDrafts(for bound: XcircuiteParameterBound) -> [SearchValueDraft] {
        let nominal = nominalValue(for: bound)
        let preferredDirection = bound.preferredDirection?.lowercased()
        let values: [Double]
        if let step = bound.step, step > 0 {
            values = steppedValues(for: bound)
        } else {
            values = fractionalValues(for: bound)
        }
        return values
            .filter { $0 != nominal }
            .map { value in
                let side = searchSide(value: value, nominal: nominal)
                return SearchValueDraft(
                    value: value,
                    priority: adaptivePriority(
                        value: value,
                        side: side,
                        preferredDirection: preferredDirection,
                        for: bound
                    ),
                    source: "Adaptive refine",
                    diagnosticCode: "adaptive-bounded-refinement"
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                return lhs.value < rhs.value
            }
    }

    private func steppedValues(for bound: XcircuiteParameterBound) -> [Double] {
        guard let step = bound.step, step > 0 else {
            return fractionalValues(for: bound)
        }
        var values: [Double] = []
        var current = bound.lowerBound
        var guardCount = 0
        while current <= bound.upperBound + (step / 2), guardCount < 1024 {
            values.append(snapped(current, for: bound))
            current += step
            guardCount += 1
        }
        values.append(bound.upperBound)
        values.append(nominalValue(for: bound))
        return unique(values.map { snapped($0, for: bound) })
    }

    private func fractionalValues(for bound: XcircuiteParameterBound) -> [Double] {
        let span = bound.upperBound - bound.lowerBound
        let values = [0, 0.25, 0.5, 0.75, 1].map { fraction in
            bound.lowerBound + span * fraction
        }
        return unique(values.map { snapped($0, for: bound) })
    }

    private func searchParameterTrace(
        bound: XcircuiteParameterBound,
        values: [SearchValueDraft],
        feedbackContext: FeedbackLearningContext?
    ) -> XcircuiteParameterCandidateSearchParameterTrace {
        let nominal = nominalValue(for: bound)
        let nominalFeedback = feedback(
            parameterName: bound.name,
            value: nominal,
            context: feedbackContext
        )
        let generatedValues = [
            XcircuiteParameterCandidateSearchValueTrace(
                value: nominal,
                priority: 0,
                source: "Base nominal",
                feedbackCandidateIDs: emptyAsNil(nominalFeedback?.candidateIDs),
                feedbackStatuses: emptyAsNil(nominalFeedback?.statuses),
                feedbackPenalty: nominalFeedback?.penalty
            ),
        ] + values.map {
            let valueFeedback = feedback(
                parameterName: bound.name,
                value: $0.value,
                context: feedbackContext
            )
            return XcircuiteParameterCandidateSearchValueTrace(
                value: $0.value,
                priority: $0.priority,
                source: $0.source,
                feedbackCandidateIDs: emptyAsNil(valueFeedback?.candidateIDs),
                feedbackStatuses: emptyAsNil(valueFeedback?.statuses),
                feedbackPenalty: valueFeedback?.penalty
            )
        }
        return XcircuiteParameterCandidateSearchParameterTrace(
            name: bound.name,
            lowerBound: bound.lowerBound,
            upperBound: bound.upperBound,
            nominalValue: nominal,
            step: bound.step,
            unit: bound.unit,
            preferredDirection: bound.preferredDirection,
            generatedValues: generatedValues
        )
    }

    private func feedbackLearningEnabled(_ strategy: String) -> Bool {
        strategy == "feedback-aware-bounded-refinement"
            || strategy == "calibrated-feedback-aware-bounded-refinement"
    }

    private func calibrationLearningEnabled(_ strategy: String) -> Bool {
        strategy == "calibrated-feedback-aware-bounded-refinement"
    }

    private func feedback(
        for assignments: [XcircuiteParameterAssignment],
        context: FeedbackLearningContext?
    ) -> AssignmentFeedback? {
        context?.assignmentFeedbackBySignature[assignmentSignature(assignments)]
    }

    private func feedback(
        parameterName: String,
        value: Double,
        context: FeedbackLearningContext?
    ) -> AssignmentFeedback? {
        guard let context else {
            return nil
        }
        let matchingFeedback = context.assignmentFeedbackBySignature.values.filter { feedback in
            feedback.parameterValues[parameterName] == value
        }
        guard !matchingFeedback.isEmpty else {
            return nil
        }
        return AssignmentFeedback(
            candidateIDs: unique(matchingFeedback.flatMap(\.candidateIDs)),
            statuses: unique(matchingFeedback.flatMap(\.statuses)),
            failedGateIDs: unique(matchingFeedback.flatMap(\.failedGateIDs)),
            diagnosticCodes: unique(matchingFeedback.flatMap(\.diagnosticCodes)),
            nextActions: unique(matchingFeedback.flatMap(\.nextActions)),
            parameterValues: [parameterName: value],
            penalty: matchingFeedback.map(\.penalty).reduce(0, +)
        )
    }

    private func feedbackDiagnostics(
        feedback: AssignmentFeedback?,
        actionID: String
    ) -> [XcircuiteParameterCandidateDiagnostic] {
        guard let feedback, feedback.penalty > 0 else {
            return []
        }
        let candidateIDs = feedback.candidateIDs.joined(separator: ",")
        return [
            XcircuiteParameterCandidateDiagnostic(
                severity: feedback.statuses.contains("rejected") ? "warning" : "info",
                code: "feedback-learned-assignment",
                message: "Candidate assignment matches rejected-plan feedback from \(candidateIDs).",
                actionID: actionID
            ),
        ]
    }

    private func calibrationAdjustment(
        action: XcircuitePlanningCandidateAction,
        assignments: [XcircuiteParameterAssignment],
        problemID: String,
        context: CalibrationContext?
    ) -> CandidateCalibrationAdjustment {
        guard let context else {
            return CandidateCalibrationAdjustment()
        }
        let sourceCandidateID = candidateID(
            problemID: problemID,
            sourceActionID: action.actionID,
            assignments: assignments
        )
        let paretoMatches = context.paretoCandidatesBySourceID[sourceCandidateID] ?? []
        var adjustment = 0.0
        var termIDs: [String] = []
        var gateIDs: [String] = []
        var sourceCandidateIDs: [String] = []
        for gateID in action.verificationGates.sorted() {
            guard let term = context.calibratedTermsByGateID[gateID] else {
                continue
            }
            let gateAdjustment = max(0, term.calibratedWeight - term.baseWeight)
            guard gateAdjustment > 0 else {
                continue
            }
            adjustment += gateAdjustment * 0.1
            termIDs.append(term.termID)
            gateIDs.append(gateID)
        }
        for candidate in paretoMatches {
            sourceCandidateIDs.append(candidate.sourceCandidateID ?? candidate.candidateID)
            adjustment += Double(max(candidate.frontierRank - 1, 0)) * 0.25
            adjustment += Double(candidate.dominatedByCandidateIDs.count) * 0.25
            let failedGates = candidate.gateStatuses
                .filter { $0.value != "passed" }
                .map(\.key)
                .sorted()
            for gateID in failedGates {
                let gateAdjustment = context.calibratedTermsByGateID[gateID].map {
                    max(0.25, $0.calibratedWeight - $0.baseWeight)
                } ?? 0.25
                adjustment += gateAdjustment
                gateIDs.append(gateID)
                if let termID = context.calibratedTermsByGateID[gateID]?.termID {
                    termIDs.append(termID)
                }
            }
            if candidate.candidateID == context.selectedParetoCandidateID
                || (!candidate.gateStatuses.isEmpty && failedGates.isEmpty) {
                adjustment -= 0.25
            }
        }
        return CandidateCalibrationAdjustment(
            adjustment: adjustment,
            termIDs: unique(termIDs),
            gateIDs: unique(gateIDs),
            sourceCandidateIDs: unique(sourceCandidateIDs)
        )
    }

    private func calibrationDiagnostics(
        calibration: CandidateCalibrationAdjustment,
        actionID: String
    ) -> [XcircuiteParameterCandidateDiagnostic] {
        guard calibration.adjustment != 0 else {
            return []
        }
        let code = calibration.adjustment < 0
            ? "cp7-calibration-promotion"
            : "cp7-calibration-penalty"
        let sources = calibration.sourceCandidateIDs.isEmpty
            ? calibration.termIDs.joined(separator: ",")
            : calibration.sourceCandidateIDs.joined(separator: ",")
        return [
            XcircuiteParameterCandidateDiagnostic(
                severity: calibration.adjustment < 0 ? "info" : "warning",
                code: code,
                message: "CP7 calibration adjustment \(calibration.adjustment) applied from \(sources).",
                actionID: actionID
            ),
        ]
    }

    private func rationale(
        base: String,
        feedback: AssignmentFeedback?,
        calibration: CandidateCalibrationAdjustment
    ) -> String {
        var parts = [base]
        if let feedback, feedback.penalty > 0 {
            let statuses = feedback.statuses.joined(separator: ",")
            parts.append("Feedback penalty \(feedback.penalty) applied from \(statuses) history.")
        }
        if calibration.adjustment != 0 {
            parts.append("CP7 calibration adjustment \(calibration.adjustment) applied.")
        }
        return parts.joined(separator: " ")
    }

    private func rationale(base: String, feedback: AssignmentFeedback?) -> String {
        guard let feedback, feedback.penalty > 0 else {
            return base
        }
        let statuses = feedback.statuses.joined(separator: ",")
        return "\(base) Feedback penalty \(feedback.penalty) applied from \(statuses) history."
    }

    private func emptyAsNil(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else {
            return nil
        }
        return values
    }

    private func adaptivePriority(
        value: Double,
        side: String,
        preferredDirection: String?,
        for bound: XcircuiteParameterBound
    ) -> Double {
        let distance = normalizedDistance(value: value, for: bound)
        guard let preferredDirection,
              preferredDirection == "increase" || preferredDirection == "decrease"
        else {
            return distance
        }
        return side == preferredDirection ? distance : distance + 0.000_001
    }

    private func searchSide(value: Double, nominal: Double) -> String {
        if value > nominal {
            return "increase"
        }
        if value < nominal {
            return "decrease"
        }
        return "nominal"
    }

    private func normalizedDistance(value: Double, for bound: XcircuiteParameterBound) -> Double {
        let span = max(bound.upperBound - bound.lowerBound, Double.ulpOfOne)
        return abs(value - nominalValue(for: bound)) / span
    }

    private func snapped(_ value: Double, for bound: XcircuiteParameterBound) -> Double {
        guard let step = bound.step, step > 0 else {
            return clamped(value, lower: bound.lowerBound, upper: bound.upperBound)
        }
        let clampedValue = clamped(value, lower: bound.lowerBound, upper: bound.upperBound)
        let steps = ((clampedValue - bound.lowerBound) / step).rounded()
        let snappedValue = bound.lowerBound + steps * step
        return clamped(snappedValue, lower: bound.lowerBound, upper: bound.upperBound)
    }

    private func normalizedCost(
        assignments: [XcircuiteParameterAssignment],
        bounds: [XcircuiteParameterBound]
    ) -> Double {
        var boundsByName: [String: XcircuiteParameterBound] = [:]
        for bound in bounds where boundsByName[bound.name] == nil {
            boundsByName[bound.name] = bound
        }
        let distances = assignments.map { assignment -> Double in
            guard let bound = boundsByName[assignment.name] else {
                return 0
            }
            let span = max(bound.upperBound - bound.lowerBound, Double.ulpOfOne)
            return abs(assignment.value - nominalValue(for: bound)) / span
        }
        return distances.reduce(0, +)
    }

    private func invalidBoundsDiagnostic(
        actionID: String,
        message: String
    ) -> XcircuiteParameterCandidateDiagnostic {
        XcircuiteParameterCandidateDiagnostic(
            severity: "warning",
            code: "invalid-parameter-bounds",
            message: message,
            actionID: actionID
        )
    }

    private func numberValue(_ value: PlanningParameterValue?) -> Double? {
        guard let value else {
            return nil
        }
        switch value {
        case .scalar(let number):
            return number
        default:
            return nil
        }
    }

    private func stringValue(_ value: PlanningParameterValue?) -> String? {
        guard let value else {
            return nil
        }
        switch value {
        case .text(let string):
            return string
        default:
            return nil
        }
    }

    private func unique(_ values: [Double]) -> [Double] {
        var seen: Set<Double> = []
        var result: [Double] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
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

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL,
        expectedFormat: ArtifactFormat
    ) async throws -> String {
        if let explicitPath {
            return try await verifiedExplicitPath(
                explicitPath,
                artifactID: artifactID,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot,
                expectedFormat: expectedFormat
            ).path
        }
        guard let artifactID else {
            throw XcircuiteParameterCandidateGenerationError.missingProblemReference
        }
        guard let reference = try await verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteParameterCandidateGenerationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        return reference.path
    }

    private func optionalPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL,
        expectedFormat: ArtifactFormat
    ) async throws -> String? {
        if let explicitPath {
            return try await verifiedExplicitPath(
                explicitPath,
                artifactID: artifactID,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot,
                expectedFormat: expectedFormat
            ).path
        }
        guard let artifactID else {
            return nil
        }
        return try await verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedFormat: expectedFormat,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )?.path
    }

    private func verifiedExplicitPath(
        _ explicitPath: String,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL,
        expectedFormat: ArtifactFormat
    ) async throws -> ArtifactReference {
        let matches = manifest.artifacts.filter { $0.path == explicitPath }
        guard matches.count <= 1 else {
            throw XcircuiteParameterCandidateGenerationError.invalidArtifactReference(
                path: explicitPath,
                reason: "multiple manifest artifacts reference the same explicit path."
            )
        }
        let reference: ArtifactReference
        if let match = matches.first {
            reference = match
        } else {
            reference = try await workspaceStore.makeArtifactReference(
                forProjectRelativePath: explicitPath,
                artifactID: artifactID,
                kind: .other,
                format: expectedFormat
            )
        }
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
        expectedFormat: ArtifactFormat,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            return nil
        }
        guard matches.count == 1 else {
            throw XcircuiteParameterCandidateGenerationError.invalidArtifactReference(
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
        _ reference: ArtifactReference,
        expectedArtifactID: String?,
        expectedFormat: ArtifactFormat,
        runID: String,
        projectRoot: URL
    ) throws {
        if let expectedArtifactID, reference.artifactID != expectedArtifactID {
            throw XcircuiteParameterCandidateGenerationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == expectedFormat else {
            throw XcircuiteParameterCandidateGenerationError.invalidArtifactReference(
                path: reference.path,
                reason: "expected \(expectedFormat.rawValue) artifact, got \(reference.kind.rawValue)/\(reference.format.rawValue)."
            )
        }
        let integrity = makeArtifactReferenceVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteParameterCandidateGenerationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }

    private func loadFeedbackLearningContext(
        request: XcircuiteParameterCandidateGenerationRequest,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> FeedbackLearningContext? {
        let rejectedPlansPath = try await optionalPath(
            explicitPath: request.rejectedPlansPath,
            artifactID: request.rejectedPlansArtifactID ?? XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .text
        )
        guard let rejectedPlansPath else {
            return nil
        }

        let records = try await readRejectedPlanRecords(path: rejectedPlansPath)
        if let mismatched = records.first(where: { $0.runID != request.runID }) {
            throw XcircuiteParameterCandidateGenerationError.runMismatch(
                expected: request.runID,
                actual: mismatched.runID
            )
        }
        let feedbackSummary = XcircuiteRejectedPlanFeedbackBuilder().makeFeedbackSummary(
            runID: request.runID,
            path: rejectedPlansPath,
            records: records
        )
        let previousCandidatesPath = try await optionalPath(
            explicitPath: request.previousParameterCandidatesPath,
            artifactID: request.previousParameterCandidatesArtifactID
                ?? XcircuitePlanningArtifactStore.parameterCandidatesArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .text
        )
        let previousCandidates: [XcircuiteParameterCandidate]
        if let previousCandidatesPath {
            previousCandidates = try await readParameterCandidates(
                path: previousCandidatesPath
            )
        } else {
            previousCandidates = []
        }

        return makeFeedbackLearningContext(
            summary: feedbackSummary,
            previousParameterCandidatesPath: previousCandidatesPath,
            previousCandidates: previousCandidates
        )
    }

    private func loadCalibrationContext(
        request: XcircuiteParameterCandidateGenerationRequest,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> CalibrationContext? {
        let useDefaultArtifacts = calibrationLearningEnabled(request.strategy)
        let thresholdProfilePath = try await optionalPath(
            explicitPath: request.metricThresholdProfilePath,
            artifactID: request.metricThresholdProfileArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .json
        )
        let costCalibrationPath = try await optionalPath(
            explicitPath: request.costCalibrationPath,
            artifactID: request.costCalibrationArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.costCalibrationArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .json
        )
        let paretoCandidatesPath = try await optionalPath(
            explicitPath: request.paretoCandidatesPath,
            artifactID: request.paretoCandidatesArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.paretoCandidatesArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            expectedFormat: .text
        )
        guard thresholdProfilePath != nil || costCalibrationPath != nil || paretoCandidatesPath != nil else {
            return nil
        }
        let thresholdProfile: XcircuiteMetricThresholdProfile? = if let thresholdProfilePath {
            try await readThresholdProfile(path: thresholdProfilePath, runID: request.runID)
        } else { nil }
        let costCalibration: XcircuiteCostCalibrationReport? = if let costCalibrationPath {
            try await readCostCalibration(path: costCalibrationPath, runID: request.runID)
        } else { nil }
        let paretoCandidates: [XcircuiteParetoCandidateSet.Candidate] = if let paretoCandidatesPath {
            try await readParetoCandidates(path: paretoCandidatesPath, runID: request.runID)
        } else { [] }
        return CalibrationContext(
            thresholdProfilePath: thresholdProfilePath,
            thresholdProfile: thresholdProfile,
            costCalibrationPath: costCalibrationPath,
            costCalibration: costCalibration,
            paretoCandidatesPath: paretoCandidatesPath,
            paretoCandidates: paretoCandidates
        )
    }

    private func makeFeedbackLearningContext(
        summary: XcircuiteRejectedPlanFeedbackSummary,
        previousParameterCandidatesPath: String?,
        previousCandidates: [XcircuiteParameterCandidate]
    ) -> FeedbackLearningContext {
        let candidatesByID = Dictionary(uniqueKeysWithValues: previousCandidates.map { ($0.candidateID, $0) })
        var feedbackBySignature: [String: AssignmentFeedback] = [:]
        var unresolvedCandidateIDs: [String] = []
        for feedback in summary.candidateFeedback {
            guard let candidate = candidatesByID[feedback.candidateID] else {
                unresolvedCandidateIDs.append(feedback.candidateID)
                continue
            }
            let signature = assignmentSignature(candidate.assignments)
            let existing = feedbackBySignature[signature]
            feedbackBySignature[signature] = AssignmentFeedback(
                candidateIDs: unique((existing?.candidateIDs ?? []) + [feedback.candidateID]),
                statuses: unique((existing?.statuses ?? []) + feedback.statuses),
                failedGateIDs: unique((existing?.failedGateIDs ?? []) + feedback.failedGateIDs),
                diagnosticCodes: unique((existing?.diagnosticCodes ?? []) + feedback.diagnosticCodes),
                nextActions: unique((existing?.nextActions ?? []) + feedback.nextActions),
                parameterValues: parameterValues(from: candidate.assignments),
                penalty: (existing?.penalty ?? 0) + feedbackPenalty(feedback)
            )
        }
        return FeedbackLearningContext(
            summary: summary,
            previousParameterCandidatesPath: previousParameterCandidatesPath,
            assignmentFeedbackBySignature: feedbackBySignature,
            unresolvedCandidateIDs: unique(unresolvedCandidateIDs)
        )
    }

    private func feedbackPenalty(_ feedback: XcircuiteRejectedPlanCandidateFeedback) -> Double {
        let weighting = XcircuiteParameterCandidateFeedbackWeighting.defaultPolicy()
        var penalty = 0.0
        if feedback.statuses.contains("rejected") {
            penalty += weighting.rejectedRetryPenalty
        }
        if feedback.statuses.contains("blocked") {
            penalty += weighting.blockedPenalty
        }
        penalty += min(
            Double(feedback.failedGateIDs.count) * weighting.failedGatePenaltyPerItem,
            weighting.failedGatePenaltyCap
        )
        penalty += min(
            Double(feedback.diagnosticCodes.count) * weighting.diagnosticPenaltyPerItem,
            weighting.diagnosticPenaltyCap
        )
        penalty += min(
            Double(feedback.nextActions.count) * weighting.nextActionPenaltyPerItem,
            weighting.nextActionPenaltyCap
        )
        return penalty
    }

    private func readThresholdProfile(
        path: String,
        runID: String
    ) async throws -> XcircuiteMetricThresholdProfile {
        let profile = try await workspaceStore.readJSON(XcircuiteMetricThresholdProfile.self, from: path)
        guard profile.runID == runID else {
            throw XcircuiteParameterCandidateGenerationError.runMismatch(
                expected: runID,
                actual: profile.runID
            )
        }
        return profile
    }

    private func readCostCalibration(
        path: String,
        runID: String
    ) async throws -> XcircuiteCostCalibrationReport {
        let report = try await workspaceStore.readJSON(XcircuiteCostCalibrationReport.self, from: path)
        guard report.runID == runID else {
            throw XcircuiteParameterCandidateGenerationError.runMismatch(
                expected: runID,
                actual: report.runID
            )
        }
        return report
    }

    private func readParetoCandidates(
        path: String,
        runID: String
    ) async throws -> [XcircuiteParetoCandidateSet.Candidate] {
        let data = try await workspaceStore.read(from: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XcircuiteParameterCandidateGenerationError.invalidParetoCandidateJSONLine(path: path, line: 1)
        }
        var candidates: [XcircuiteParetoCandidateSet.Candidate] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                let candidate = try JSONDecoder().decode(
                    XcircuiteParetoCandidateSet.Candidate.self,
                    from: data
                )
                guard candidate.runID == runID else {
                    throw XcircuiteParameterCandidateGenerationError.runMismatch(
                        expected: runID,
                        actual: candidate.runID
                    )
                }
                candidates.append(candidate)
            } catch let error as XcircuiteParameterCandidateGenerationError {
                throw error
            } catch {
                throw XcircuiteParameterCandidateGenerationError.invalidParetoCandidateJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return candidates
    }

    private func readParameterCandidates(path: String) async throws -> [XcircuiteParameterCandidate] {
        let data = try await workspaceStore.read(from: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XcircuiteParameterCandidateGenerationError.invalidPreviousParameterCandidateJSONLine(path: path, line: 1)
        }
        var candidates: [XcircuiteParameterCandidate] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                candidates.append(try JSONDecoder().decode(XcircuiteParameterCandidate.self, from: data))
            } catch {
                throw XcircuiteParameterCandidateGenerationError.invalidPreviousParameterCandidateJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return candidates
    }

    private func readRejectedPlanRecords(path: String) async throws -> [XcircuiteRejectedPlanRecord] {
        let data = try await workspaceStore.read(from: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XcircuiteParameterCandidateGenerationError.invalidRejectedPlanJSONLine(path: path, line: 1)
        }
        var records: [XcircuiteRejectedPlanRecord] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                records.append(try JSONDecoder().decode(XcircuiteRejectedPlanRecord.self, from: data))
            } catch {
                throw XcircuiteParameterCandidateGenerationError.invalidRejectedPlanJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return records
    }

    private func candidateID(problemID: String, draft: CandidateDraft) -> String {
        candidateID(
            problemID: problemID,
            sourceActionID: draft.sourceActionID,
            assignments: draft.assignments
        )
    }

    private func candidateID(
        problemID: String,
        sourceActionID: String,
        assignments: [XcircuiteParameterAssignment]
    ) -> String {
        identifier("\(problemID)-parameter-candidate-\(sourceActionID)-\(assignmentSignature(assignments))")
    }

    private func assignmentSignature(_ assignments: [XcircuiteParameterAssignment]) -> String {
        assignments
            .sorted { $0.name < $1.name }
            .map { assignment in
                let unit = assignment.unit.map { ":\($0)" } ?? ""
                return "\(assignment.name)=\(canonicalNumber(assignment.value))\(unit)"
            }
            .joined(separator: ",")
    }

    private func parameterValues(from assignments: [XcircuiteParameterAssignment]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: assignments.map { ($0.name, $0.value) })
    }

    private func canonicalNumber(_ value: Double) -> String {
        String(format: "%.12g", value)
    }

    private func identifier(_ rawValue: String) -> String {
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
        return trimmed.isEmpty ? "parameter-candidate" : trimmed
    }
}

public extension XcircuiteParameterCandidateGenerator {
    struct ParameterCandidateGeneration: Sendable, Hashable {
        public var candidates: [XcircuiteParameterCandidate]
        public var searchTrace: XcircuiteParameterCandidateSearchTrace
        public var diagnostics: [XcircuiteParameterCandidateDiagnostic]

        public init(
            candidates: [XcircuiteParameterCandidate],
            searchTrace: XcircuiteParameterCandidateSearchTrace,
            diagnostics: [XcircuiteParameterCandidateDiagnostic]
        ) {
            self.candidates = candidates
            self.searchTrace = searchTrace
            self.diagnostics = diagnostics
        }
    }
}

private struct CandidateDraftGeneration: Sendable, Hashable {
    var drafts: [CandidateDraft]
    var actionTrace: XcircuiteParameterCandidateSearchActionTrace
}

private struct CandidateDraft: Sendable, Hashable {
    var sourceActionID: String
    var sourceOperationID: String
    var sourceObjectiveIDs: [String]
    var assignments: [XcircuiteParameterAssignment]
    var normalizedCost: Double
    var priority: Double
    var verificationGates: [String]
    var rationale: String
    var diagnostics: [XcircuiteParameterCandidateDiagnostic]
    var calibrationAdjustment: CandidateCalibrationAdjustment
    var sortKey: String
}

private struct SearchValueDraft: Sendable, Hashable {
    var value: Double
    var priority: Double
    var source: String
    var diagnosticCode: String?
}

private struct FeedbackLearningContext: Sendable, Hashable {
    var summary: XcircuiteRejectedPlanFeedbackSummary
    var previousParameterCandidatesPath: String?
    var assignmentFeedbackBySignature: [String: AssignmentFeedback]
    var unresolvedCandidateIDs: [String]

    func trace(strategy: String) -> XcircuiteParameterCandidateSearchFeedbackTrace {
        XcircuiteParameterCandidateSearchFeedbackTrace(
            strategy: strategy,
            rejectedPlansPath: summary.rejectedPlansPath,
            previousParameterCandidatesPath: previousParameterCandidatesPath,
            recordCount: summary.recordCount,
            candidateFeedbackCount: summary.candidateFeedback.count,
            learnedAssignmentCount: assignmentFeedbackBySignature.count,
            unresolvedCandidateIDs: unresolvedCandidateIDs
        )
    }
}

private struct AssignmentFeedback: Sendable, Hashable {
    var candidateIDs: [String]
    var statuses: [String]
    var failedGateIDs: [String]
    var diagnosticCodes: [String]
    var nextActions: [String]
    var parameterValues: [String: Double]
    var penalty: Double
}

private struct CalibrationContext: Sendable, Hashable {
    var thresholdProfilePath: String?
    var thresholdProfile: XcircuiteMetricThresholdProfile?
    var costCalibrationPath: String?
    var costCalibration: XcircuiteCostCalibrationReport?
    var paretoCandidatesPath: String?
    var paretoCandidates: [XcircuiteParetoCandidateSet.Candidate]
    var calibratedTermsByGateID: [String: XcircuiteCostCalibrationReport.Term]
    var paretoCandidatesBySourceID: [String: [XcircuiteParetoCandidateSet.Candidate]]
    var selectedParetoCandidateID: String?

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
        var paretoBySourceID: [String: [XcircuiteParetoCandidateSet.Candidate]] = [:]
        for candidate in paretoCandidates {
            paretoBySourceID[candidate.candidateID, default: []].append(candidate)
            if let sourceCandidateID = candidate.sourceCandidateID {
                paretoBySourceID[sourceCandidateID, default: []].append(candidate)
            }
        }
        self.paretoCandidatesBySourceID = paretoBySourceID
        self.selectedParetoCandidateID = paretoCandidates.first {
            $0.gateStatuses.values.contains { $0 == "passed" }
        }?.candidateID
    }

    func trace(
        strategy: String,
        appliedDrafts: [CandidateDraft]
    ) -> XcircuiteParameterCandidateCalibrationTrace {
        let appliedAdjustments = appliedDrafts.map(\.calibrationAdjustment)
        return XcircuiteParameterCandidateCalibrationTrace(
            strategy: strategy,
            metricThresholdProfilePath: thresholdProfilePath,
            costCalibrationPath: costCalibrationPath,
            paretoCandidatesPath: paretoCandidatesPath,
            thresholdCount: thresholdProfile?.thresholds.count ?? 0,
            calibratedTermCount: costCalibration?.calibratedTerms.count ?? 0,
            observationCount: costCalibration?.observations.count ?? 0,
            paretoCandidateCount: paretoCandidates.count,
            appliedCandidateCount: appliedAdjustments.count,
            matchedSourceCandidateIDs: unique(
                appliedAdjustments.flatMap(\.sourceCandidateIDs)
            ),
            matchedGateIDs: unique(appliedAdjustments.flatMap(\.gateIDs)),
            diagnostics: diagnostics()
        )
    }

    private func diagnostics() -> [String] {
        var diagnostics: [String] = []
        if thresholdProfilePath != nil && thresholdProfile == nil {
            diagnostics.append("metric threshold profile path was provided but no profile was loaded")
        }
        if costCalibrationPath == nil {
            diagnostics.append("cost calibration artifact was not available")
        }
        if paretoCandidatesPath == nil {
            diagnostics.append("pareto candidate artifact was not available")
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
}

private struct CandidateCalibrationAdjustment: Sendable, Hashable {
    var adjustment: Double
    var termIDs: [String]
    var gateIDs: [String]
    var sourceCandidateIDs: [String]

    init(
        adjustment: Double = 0,
        termIDs: [String] = [],
        gateIDs: [String] = [],
        sourceCandidateIDs: [String] = []
    ) {
        self.adjustment = adjustment
        self.termIDs = termIDs
        self.gateIDs = gateIDs
        self.sourceCandidateIDs = sourceCandidateIDs
    }
}
