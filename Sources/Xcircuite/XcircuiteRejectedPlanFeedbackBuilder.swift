import Foundation

public struct XcircuiteRejectedPlanFeedbackBuilder: Sendable {
    public init() {}

    public func makeFeedbackSummary(
        runID: String,
        path: String,
        records: [XcircuiteRejectedPlanRecord]
    ) -> XcircuiteRejectedPlanFeedbackSummary {
        var feedbackByCandidateID: [String: CandidateFeedbackAccumulator] = [:]
        var globalFeedbackRecords: [XcircuiteRejectedPlanGlobalFeedback] = []
        for record in records {
            guard !record.sourceParameterCandidateIDs.isEmpty else {
                globalFeedbackRecords.append(globalFeedback(from: record))
                continue
            }
            for candidateID in record.sourceParameterCandidateIDs {
                var feedback = feedbackByCandidateID[candidateID] ?? CandidateFeedbackAccumulator(candidateID: candidateID)
                feedback.statuses.append(record.status)
                feedback.planIDs.append(record.planID)
                feedback.failedStepIDs.append(contentsOf: record.failedStepIDs)
                feedback.failedGateIDs.append(contentsOf: record.failedGateIDs)
                feedback.diagnosticCodes.append(contentsOf: record.diagnostics.map(\.code))
                feedback.diagnosticClasses.append(contentsOf: diagnosticClasses(from: record))
                feedback.nextActions.append(contentsOf: record.nextActions)
                feedbackByCandidateID[candidateID] = feedback
            }
        }
        let candidateFeedback = feedbackByCandidateID.values
            .map { $0.makeFeedback() }
            .sorted { $0.candidateID < $1.candidateID }
        let excludedCandidateIDs = candidateFeedback
            .filter { $0.statuses.contains("rejected") }
            .map(\.candidateID)

        return XcircuiteRejectedPlanFeedbackSummary(
            runID: runID,
            rejectedPlansPath: path,
            recordCount: records.count,
            candidateFeedback: candidateFeedback,
            globalFeedback: globalFeedbackRecords.sorted { $0.feedbackID < $1.feedbackID },
            diagnosticClassCounts: diagnosticClassCounts(records),
            excludedCandidateIDs: excludedCandidateIDs
        )
    }

    private func globalFeedback(from record: XcircuiteRejectedPlanRecord) -> XcircuiteRejectedPlanGlobalFeedback {
        XcircuiteRejectedPlanGlobalFeedback(
            feedbackID: record.rejectionID,
            verificationMode: record.verificationMode,
            statuses: [record.status],
            planIDs: [record.planID],
            failedStepIDs: unique(record.failedStepIDs),
            failedGateIDs: unique(record.failedGateIDs),
            diagnosticCodes: unique(record.diagnostics.map(\.code)),
            diagnosticClasses: unique(diagnosticClasses(from: record)),
            diagnosticGateIDs: unique(record.diagnostics.compactMap(\.gateID)),
            nextActions: unique(record.nextActions)
        )
    }

    private func diagnosticClasses(from record: XcircuiteRejectedPlanRecord) -> [String] {
        let classifications = record.diagnosticClassifications.isEmpty
            ? XcircuiteRejectedPlanDiagnosticClassifier().classify(record: record)
            : record.diagnosticClassifications
        return classifications.map(\.diagnosticClass.rawValue)
    }

    private func diagnosticClassCounts(_ records: [XcircuiteRejectedPlanRecord]) -> [String: Int] {
        records.reduce(into: [String: Int]()) { counts, record in
            for diagnosticClass in diagnosticClasses(from: record) {
                counts[diagnosticClass, default: 0] += 1
            }
        }
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
}

private struct CandidateFeedbackAccumulator: Sendable, Hashable {
    var candidateID: String
    var statuses: [String] = []
    var planIDs: [String] = []
    var failedStepIDs: [String] = []
    var failedGateIDs: [String] = []
    var diagnosticCodes: [String] = []
    var diagnosticClasses: [String] = []
    var nextActions: [String] = []

    func makeFeedback() -> XcircuiteRejectedPlanCandidateFeedback {
        XcircuiteRejectedPlanCandidateFeedback(
            candidateID: candidateID,
            statuses: unique(statuses),
            planIDs: unique(planIDs),
            failedStepIDs: unique(failedStepIDs),
            failedGateIDs: unique(failedGateIDs),
            diagnosticCodes: unique(diagnosticCodes),
            diagnosticClasses: unique(diagnosticClasses),
            nextActions: unique(nextActions)
        )
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
}
