import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanExecutionResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var candidatePlanPath: String
    public var planExecutionArtifact: ArtifactReference
    public var designDiffArtifact: ArtifactReference?
    public var producedArtifacts: [ArtifactReference]
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        candidatePlanPath: String,
        planExecutionArtifact: ArtifactReference,
        designDiffArtifact: ArtifactReference? = nil,
        producedArtifacts: [ArtifactReference],
        nextActions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.candidatePlanPath = candidatePlanPath
        self.planExecutionArtifact = planExecutionArtifact
        self.designDiffArtifact = designDiffArtifact
        self.producedArtifacts = producedArtifacts
        self.nextActions = nextActions
    }
}
