import Foundation

public struct XcircuiteRejectedPlanGlobalFeedback: Codable, Sendable, Hashable {
    public var feedbackID: String
    public var verificationMode: String
    public var statuses: [String]
    public var planIDs: [String]
    public var failedStepIDs: [String]
    public var failedGateIDs: [String]
    public var diagnosticCodes: [String]
    public var diagnosticClasses: [String]
    public var diagnosticGateIDs: [String]
    public var nextActions: [String]

    public init(
        feedbackID: String,
        verificationMode: String,
        statuses: [String],
        planIDs: [String],
        failedStepIDs: [String],
        failedGateIDs: [String],
        diagnosticCodes: [String],
        diagnosticClasses: [String] = [],
        diagnosticGateIDs: [String],
        nextActions: [String]
    ) {
        self.feedbackID = feedbackID
        self.verificationMode = verificationMode
        self.statuses = statuses
        self.planIDs = planIDs
        self.failedStepIDs = failedStepIDs
        self.failedGateIDs = failedGateIDs
        self.diagnosticCodes = diagnosticCodes
        self.diagnosticClasses = diagnosticClasses
        self.diagnosticGateIDs = diagnosticGateIDs
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case feedbackID
        case verificationMode
        case statuses
        case planIDs
        case failedStepIDs
        case failedGateIDs
        case diagnosticCodes
        case diagnosticClasses
        case diagnosticGateIDs
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feedbackID = try container.decode(String.self, forKey: .feedbackID)
        verificationMode = try container.decode(String.self, forKey: .verificationMode)
        statuses = try container.decode([String].self, forKey: .statuses)
        planIDs = try container.decode([String].self, forKey: .planIDs)
        failedStepIDs = try container.decode([String].self, forKey: .failedStepIDs)
        failedGateIDs = try container.decode([String].self, forKey: .failedGateIDs)
        diagnosticCodes = try container.decode([String].self, forKey: .diagnosticCodes)
        diagnosticClasses = try container.decodeIfPresent([String].self, forKey: .diagnosticClasses) ?? []
        diagnosticGateIDs = try container.decode([String].self, forKey: .diagnosticGateIDs)
        nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feedbackID, forKey: .feedbackID)
        try container.encode(verificationMode, forKey: .verificationMode)
        try container.encode(statuses, forKey: .statuses)
        try container.encode(planIDs, forKey: .planIDs)
        try container.encode(failedStepIDs, forKey: .failedStepIDs)
        try container.encode(failedGateIDs, forKey: .failedGateIDs)
        try container.encode(diagnosticCodes, forKey: .diagnosticCodes)
        try container.encode(diagnosticClasses, forKey: .diagnosticClasses)
        try container.encode(diagnosticGateIDs, forKey: .diagnosticGateIDs)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
