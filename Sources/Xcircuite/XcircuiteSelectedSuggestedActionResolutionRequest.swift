import Foundation

public struct XcircuiteSelectedSuggestedActionResolutionRequest: Sendable, Hashable, Codable {
    public var runID: String
    public var actionID: String?

    public init(runID: String, actionID: String? = nil) {
        self.runID = runID
        self.actionID = actionID
    }
}
