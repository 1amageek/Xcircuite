import Foundation

public struct PlanningDRCRule: Sendable, Hashable, Codable {
    public var ruleID: String
    public var kind: String
    public var layer: String
    public var requiredValue: Double

    public init(ruleID: String, kind: String, layer: String, requiredValue: Double) {
        self.ruleID = ruleID
        self.kind = kind
        self.layer = layer
        self.requiredValue = requiredValue
    }
}
