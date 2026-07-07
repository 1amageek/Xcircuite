import Foundation

public struct XcircuiteParameterCandidateFeedbackWeighting: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var source: String
    public var sourceTermIDs: [String]
    public var rejectedExclusionPenalty: Double
    public var rejectedRetryPenalty: Double
    public var blockedPenalty: Double
    public var failedGatePenaltyPerItem: Double
    public var failedGatePenaltyCap: Double
    public var diagnosticPenaltyPerItem: Double
    public var diagnosticPenaltyCap: Double
    public var nextActionPenaltyPerItem: Double
    public var nextActionPenaltyCap: Double

    public init(
        schemaVersion: Int = 1,
        source: String,
        sourceTermIDs: [String] = [],
        rejectedExclusionPenalty: Double,
        rejectedRetryPenalty: Double,
        blockedPenalty: Double,
        failedGatePenaltyPerItem: Double,
        failedGatePenaltyCap: Double,
        diagnosticPenaltyPerItem: Double,
        diagnosticPenaltyCap: Double,
        nextActionPenaltyPerItem: Double,
        nextActionPenaltyCap: Double
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.sourceTermIDs = sourceTermIDs
        self.rejectedExclusionPenalty = rejectedExclusionPenalty
        self.rejectedRetryPenalty = rejectedRetryPenalty
        self.blockedPenalty = blockedPenalty
        self.failedGatePenaltyPerItem = failedGatePenaltyPerItem
        self.failedGatePenaltyCap = failedGatePenaltyCap
        self.diagnosticPenaltyPerItem = diagnosticPenaltyPerItem
        self.diagnosticPenaltyCap = diagnosticPenaltyCap
        self.nextActionPenaltyPerItem = nextActionPenaltyPerItem
        self.nextActionPenaltyCap = nextActionPenaltyCap
    }

    public static func defaultPolicy() -> XcircuiteParameterCandidateFeedbackWeighting {
        XcircuiteParameterCandidateFeedbackWeighting(
            source: "built-in-default",
            rejectedExclusionPenalty: 1_000_000,
            rejectedRetryPenalty: 10,
            blockedPenalty: 0.3,
            failedGatePenaltyPerItem: 0.1,
            failedGatePenaltyCap: 0.5,
            diagnosticPenaltyPerItem: 0.05,
            diagnosticPenaltyCap: 0.25,
            nextActionPenaltyPerItem: 0.02,
            nextActionPenaltyCap: 0.2
        )
    }
}
