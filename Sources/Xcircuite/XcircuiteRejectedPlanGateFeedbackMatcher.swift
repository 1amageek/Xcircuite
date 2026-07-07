import Foundation

struct XcircuiteRejectedPlanGateFeedbackMatcher: Sendable {
    func matchedCandidateFeedback(
        candidateID: String,
        verificationGates: [String],
        globalFeedback: [XcircuiteRejectedPlanGlobalFeedback]
    ) -> XcircuiteRejectedPlanCandidateFeedback? {
        var statuses: [String] = []
        var planIDs: [String] = []
        var failedStepIDs: [String] = []
        var failedGateIDs: [String] = []
        var diagnosticCodes: [String] = []
        var diagnosticClasses: [String] = []
        var nextActions: [String] = []

        for feedback in globalFeedback {
            let matchedGateIDs = matchedFeedbackGateIDs(
                candidateGateIDs: verificationGates,
                feedbackGateIDs: unique(feedback.failedGateIDs + feedback.diagnosticGateIDs)
            )
            guard !matchedGateIDs.isEmpty else {
                continue
            }
            statuses.append(contentsOf: feedback.statuses.map { "global:\($0)" })
            planIDs.append(contentsOf: feedback.planIDs)
            failedStepIDs.append(contentsOf: feedback.failedStepIDs)
            failedGateIDs.append(contentsOf: matchedGateIDs)
            diagnosticCodes.append(contentsOf: feedback.diagnosticCodes)
            diagnosticClasses.append(contentsOf: feedback.diagnosticClasses)
            nextActions.append(contentsOf: nextActionsMatching(matchedGateIDs, in: feedback.nextActions))
        }

        guard !failedGateIDs.isEmpty || !diagnosticCodes.isEmpty || !nextActions.isEmpty else {
            return nil
        }
        return XcircuiteRejectedPlanCandidateFeedback(
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

    private func matchedFeedbackGateIDs(
        candidateGateIDs: [String],
        feedbackGateIDs: [String]
    ) -> [String] {
        feedbackGateIDs.filter { feedbackGateID in
            candidateGateIDs.contains { candidateGateID in
                gateIDsMatch(candidateGateID, feedbackGateID)
            }
        }
    }

    private func gateIDsMatch(_ candidateGateID: String, _ feedbackGateID: String) -> Bool {
        if candidateGateID == feedbackGateID {
            return true
        }
        let candidateTokens = gateDomainTokens(candidateGateID)
        let feedbackTokens = gateDomainTokens(feedbackGateID)
        return !candidateTokens.isEmpty && !candidateTokens.isDisjoint(with: feedbackTokens)
    }

    private func gateDomainTokens(_ gateID: String) -> Set<String> {
        let domainTokens: Set<String> = [
            "approval",
            "artifact",
            "density",
            "drc",
            "lvs",
            "pex",
            "simulation",
            "timing",
        ]
        let tokens = gateID.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return Set(tokens).intersection(domainTokens)
    }

    private func nextActionsMatching(_ gateIDs: [String], in nextActions: [String]) -> [String] {
        let matching = nextActions.filter { action in
            gateIDs.contains { action.contains($0) }
        }
        return matching.isEmpty ? nextActions : matching
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
