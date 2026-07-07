import Foundation

public struct XcircuiteRejectedPlanFeedbackSummary: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var rejectedPlansPath: String?
    public var recordCount: Int
    public var candidateFeedback: [XcircuiteRejectedPlanCandidateFeedback]
    public var globalFeedback: [XcircuiteRejectedPlanGlobalFeedback]
    public var diagnosticClassCounts: [String: Int]
    public var excludedCandidateIDs: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        rejectedPlansPath: String?,
        recordCount: Int,
        candidateFeedback: [XcircuiteRejectedPlanCandidateFeedback],
        globalFeedback: [XcircuiteRejectedPlanGlobalFeedback] = [],
        diagnosticClassCounts: [String: Int] = [:],
        excludedCandidateIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.rejectedPlansPath = rejectedPlansPath
        self.recordCount = recordCount
        self.candidateFeedback = candidateFeedback
        self.globalFeedback = globalFeedback
        self.diagnosticClassCounts = diagnosticClassCounts
        self.excludedCandidateIDs = excludedCandidateIDs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case rejectedPlansPath
        case recordCount
        case candidateFeedback
        case globalFeedback
        case diagnosticClassCounts
        case excludedCandidateIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        rejectedPlansPath = try container.decodeIfPresent(String.self, forKey: .rejectedPlansPath)
        recordCount = try container.decode(Int.self, forKey: .recordCount)
        candidateFeedback = try container.decode(
            [XcircuiteRejectedPlanCandidateFeedback].self,
            forKey: .candidateFeedback
        )
        globalFeedback = try container.decodeIfPresent(
            [XcircuiteRejectedPlanGlobalFeedback].self,
            forKey: .globalFeedback
        ) ?? []
        diagnosticClassCounts = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .diagnosticClassCounts
        ) ?? [:]
        excludedCandidateIDs = try container.decode([String].self, forKey: .excludedCandidateIDs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encodeIfPresent(rejectedPlansPath, forKey: .rejectedPlansPath)
        try container.encode(recordCount, forKey: .recordCount)
        try container.encode(candidateFeedback, forKey: .candidateFeedback)
        try container.encode(globalFeedback, forKey: .globalFeedback)
        try container.encode(diagnosticClassCounts, forKey: .diagnosticClassCounts)
        try container.encode(excludedCandidateIDs, forKey: .excludedCandidateIDs)
    }
}

public struct XcircuiteRejectedPlanCandidateFeedback: Codable, Sendable, Hashable {
    public var candidateID: String
    public var statuses: [String]
    public var planIDs: [String]
    public var failedStepIDs: [String]
    public var failedGateIDs: [String]
    public var diagnosticCodes: [String]
    public var diagnosticClasses: [String]
    public var nextActions: [String]

    public init(
        candidateID: String,
        statuses: [String],
        planIDs: [String],
        failedStepIDs: [String],
        failedGateIDs: [String],
        diagnosticCodes: [String],
        diagnosticClasses: [String] = [],
        nextActions: [String]
    ) {
        self.candidateID = candidateID
        self.statuses = statuses
        self.planIDs = planIDs
        self.failedStepIDs = failedStepIDs
        self.failedGateIDs = failedGateIDs
        self.diagnosticCodes = diagnosticCodes
        self.diagnosticClasses = diagnosticClasses
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case candidateID
        case statuses
        case planIDs
        case failedStepIDs
        case failedGateIDs
        case diagnosticCodes
        case diagnosticClasses
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateID = try container.decode(String.self, forKey: .candidateID)
        statuses = try container.decode([String].self, forKey: .statuses)
        planIDs = try container.decode([String].self, forKey: .planIDs)
        failedStepIDs = try container.decode([String].self, forKey: .failedStepIDs)
        failedGateIDs = try container.decode([String].self, forKey: .failedGateIDs)
        diagnosticCodes = try container.decode([String].self, forKey: .diagnosticCodes)
        diagnosticClasses = try container.decodeIfPresent([String].self, forKey: .diagnosticClasses) ?? []
        nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(candidateID, forKey: .candidateID)
        try container.encode(statuses, forKey: .statuses)
        try container.encode(planIDs, forKey: .planIDs)
        try container.encode(failedStepIDs, forKey: .failedStepIDs)
        try container.encode(failedGateIDs, forKey: .failedGateIDs)
        try container.encode(diagnosticCodes, forKey: .diagnosticCodes)
        try container.encode(diagnosticClasses, forKey: .diagnosticClasses)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
