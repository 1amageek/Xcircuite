import Foundation

public struct XcircuiteParameterCandidateSearchValueTrace: Codable, Sendable, Hashable {
    public var value: Double
    public var priority: Double
    public var source: String
    public var feedbackCandidateIDs: [String]?
    public var feedbackStatuses: [String]?
    public var feedbackPenalty: Double?

    public init(
        value: Double,
        priority: Double,
        source: String,
        feedbackCandidateIDs: [String]? = nil,
        feedbackStatuses: [String]? = nil,
        feedbackPenalty: Double? = nil
    ) {
        self.value = value
        self.priority = priority
        self.source = source
        self.feedbackCandidateIDs = feedbackCandidateIDs
        self.feedbackStatuses = feedbackStatuses
        self.feedbackPenalty = feedbackPenalty
    }
}
