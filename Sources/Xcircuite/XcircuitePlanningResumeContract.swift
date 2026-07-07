import Foundation

public struct XcircuitePlanningResumeContract: Codable, Sendable, Hashable {
    public var mode: String
    public var requiredArtifacts: [String]
    public var blockedStates: [String]

    public init(
        mode: String,
        requiredArtifacts: [String],
        blockedStates: [String]
    ) {
        self.mode = mode
        self.requiredArtifacts = requiredArtifacts
        self.blockedStates = blockedStates
    }
}
