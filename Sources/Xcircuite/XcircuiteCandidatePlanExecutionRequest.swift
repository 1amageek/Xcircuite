import Foundation

public struct XcircuiteCandidatePlanExecutionRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var candidatePlanArtifactID: String?
    public var candidatePlanPath: String?
    public var actor: String

    public init(
        runID: String,
        candidatePlanArtifactID: String? = nil,
        candidatePlanPath: String? = nil,
        actor: String = "xcircuite-flow"
    ) {
        self.runID = runID
        self.candidatePlanArtifactID = candidatePlanArtifactID
        self.candidatePlanPath = candidatePlanPath
        self.actor = actor
    }
}
