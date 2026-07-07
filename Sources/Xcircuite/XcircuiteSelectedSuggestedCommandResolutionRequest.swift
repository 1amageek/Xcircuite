import Foundation

public struct XcircuiteSelectedSuggestedCommandResolutionRequest: Sendable, Hashable, Codable {
    public var runID: String
    public var commandID: String?

    public init(runID: String, commandID: String? = nil) {
        self.runID = runID
        self.commandID = commandID
    }
}
