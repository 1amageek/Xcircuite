import Foundation

public struct XcircuiteParameterCandidateSearchFeedbackTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var strategy: String
    public var rejectedPlansPath: String?
    public var previousParameterCandidatesPath: String?
    public var recordCount: Int
    public var candidateFeedbackCount: Int
    public var learnedAssignmentCount: Int
    public var unresolvedCandidateIDs: [String]

    public init(
        schemaVersion: Int = 1,
        strategy: String,
        rejectedPlansPath: String? = nil,
        previousParameterCandidatesPath: String? = nil,
        recordCount: Int,
        candidateFeedbackCount: Int,
        learnedAssignmentCount: Int,
        unresolvedCandidateIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.strategy = strategy
        self.rejectedPlansPath = rejectedPlansPath
        self.previousParameterCandidatesPath = previousParameterCandidatesPath
        self.recordCount = recordCount
        self.candidateFeedbackCount = candidateFeedbackCount
        self.learnedAssignmentCount = learnedAssignmentCount
        self.unresolvedCandidateIDs = unresolvedCandidateIDs
    }
}
