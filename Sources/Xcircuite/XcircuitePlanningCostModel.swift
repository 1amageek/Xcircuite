import Foundation

public struct XcircuitePlanningCostModel: Codable, Sendable, Hashable {
    public var strategy: String
    public var terms: [XcircuitePlanningCostTerm]

    public init(
        strategy: String,
        terms: [XcircuitePlanningCostTerm]
    ) {
        self.strategy = strategy
        self.terms = terms
    }
}

public struct XcircuitePlanningCostTerm: Codable, Sendable, Hashable {
    public var termID: String
    public var weight: Double
    public var direction: String
    public var description: String

    public init(
        termID: String,
        weight: Double,
        direction: String,
        description: String
    ) {
        self.termID = termID
        self.weight = weight
        self.direction = direction
        self.description = description
    }
}
