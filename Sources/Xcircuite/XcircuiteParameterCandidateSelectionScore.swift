import Foundation

public struct XcircuiteParameterCandidateSelectionScore: Codable, Sendable, Hashable {
    public var candidateID: String
    public var rank: Int
    public var baseCost: Double
    public var feedbackPenalty: Double
    public var totalScore: Double
    public var feedbackPenaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent]
    public var selectionState: String
    public var feedbackStatuses: [String]
    public var failedGateIDs: [String]
    public var diagnosticCodes: [String]
    public var nextActions: [String]
    public var exclusionReason: String?

    public init(
        candidateID: String,
        rank: Int,
        baseCost: Double,
        feedbackPenalty: Double,
        totalScore: Double,
        feedbackPenaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent] = [],
        selectionState: String,
        feedbackStatuses: [String],
        failedGateIDs: [String],
        diagnosticCodes: [String],
        nextActions: [String],
        exclusionReason: String? = nil
    ) {
        self.candidateID = candidateID
        self.rank = rank
        self.baseCost = baseCost
        self.feedbackPenalty = feedbackPenalty
        self.totalScore = totalScore
        self.feedbackPenaltyComponents = feedbackPenaltyComponents
        self.selectionState = selectionState
        self.feedbackStatuses = feedbackStatuses
        self.failedGateIDs = failedGateIDs
        self.diagnosticCodes = diagnosticCodes
        self.nextActions = nextActions
        self.exclusionReason = exclusionReason
    }
}
