import Foundation

public struct XcircuiteSymbolicPlannerFamilySelectionScoreComponent: Codable, Sendable, Hashable {
    public var termID: String
    public var contribution: Int
    public var reason: String

    public init(termID: String, contribution: Int, reason: String) {
        self.termID = termID
        self.contribution = contribution
        self.reason = reason
    }
}
