import Foundation

public struct XcircuiteParameterCandidateFeedbackPenaltyComponent: Codable, Sendable, Hashable {
    public var componentID: String
    public var itemCount: Int
    public var unitPenalty: Double
    public var cap: Double?
    public var appliedPenalty: Double

    public init(
        componentID: String,
        itemCount: Int,
        unitPenalty: Double,
        cap: Double? = nil,
        appliedPenalty: Double
    ) {
        self.componentID = componentID
        self.itemCount = itemCount
        self.unitPenalty = unitPenalty
        self.cap = cap
        self.appliedPenalty = appliedPenalty
    }
}
