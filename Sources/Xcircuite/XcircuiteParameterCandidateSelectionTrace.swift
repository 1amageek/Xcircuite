import Foundation

public struct XcircuiteParameterCandidateSelectionTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var strategy: String
    public var parameterCandidatesPath: String
    public var rejectedPlansPath: String?
    public var feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting
    public var includeRejectedCandidates: Bool
    public var explicitCandidateID: String?
    public var explicitRank: Int?
    public var selectedCandidateID: String
    public var selectedTotalScore: Double
    public var rankedCandidates: [XcircuiteParameterCandidateSelectionScore]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        strategy: String,
        parameterCandidatesPath: String,
        rejectedPlansPath: String?,
        feedbackWeighting: XcircuiteParameterCandidateFeedbackWeighting,
        includeRejectedCandidates: Bool,
        explicitCandidateID: String? = nil,
        explicitRank: Int? = nil,
        selectedCandidateID: String,
        selectedTotalScore: Double,
        rankedCandidates: [XcircuiteParameterCandidateSelectionScore]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.strategy = strategy
        self.parameterCandidatesPath = parameterCandidatesPath
        self.rejectedPlansPath = rejectedPlansPath
        self.feedbackWeighting = feedbackWeighting
        self.includeRejectedCandidates = includeRejectedCandidates
        self.explicitCandidateID = explicitCandidateID
        self.explicitRank = explicitRank
        self.selectedCandidateID = selectedCandidateID
        self.selectedTotalScore = selectedTotalScore
        self.rankedCandidates = rankedCandidates
    }
}
