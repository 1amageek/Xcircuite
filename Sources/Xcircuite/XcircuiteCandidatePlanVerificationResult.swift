import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanVerificationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var accepted: Bool
    public var candidatePlanPath: String
    public var planVerificationArtifact: ArtifactReference
    public var rejectedPlansArtifact: ArtifactReference?
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        accepted: Bool,
        candidatePlanPath: String,
        planVerificationArtifact: ArtifactReference,
        rejectedPlansArtifact: ArtifactReference? = nil,
        nextActions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.accepted = accepted
        self.candidatePlanPath = candidatePlanPath
        self.planVerificationArtifact = planVerificationArtifact
        self.rejectedPlansArtifact = rejectedPlansArtifact
        self.nextActions = nextActions
    }
}
