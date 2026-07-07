import Foundation

public struct XcircuiteCandidatePlanVerificationRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var candidatePlanArtifactID: String?
    public var candidatePlanPath: String?
    public var verificationMode: String

    public init(
        runID: String,
        candidatePlanArtifactID: String? = nil,
        candidatePlanPath: String? = nil,
        verificationMode: String = "preflight"
    ) {
        self.runID = runID
        self.candidatePlanArtifactID = candidatePlanArtifactID
        self.candidatePlanPath = candidatePlanPath
        self.verificationMode = verificationMode
    }
}
