import Foundation

public struct XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var policyID: String
    public var minimumCaseCount: Int
    public var requiredCoverageTags: [String]
    public var requiredSourceArtifactFormats: [String]
    public var requiredSignoffArtifactIDs: [String]
    public var requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
    public var requireReadyOracleEvidence: Bool

    public init(
        schemaVersion: Int = 1,
        policyID: String,
        minimumCaseCount: Int = 1,
        requiredCoverageTags: [String] = [],
        requiredSourceArtifactFormats: [String] = [],
        requiredSignoffArtifactIDs: [String] = [],
        requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily] = [],
        requireReadyOracleEvidence: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.minimumCaseCount = minimumCaseCount
        self.requiredCoverageTags = requiredCoverageTags
        self.requiredSourceArtifactFormats = requiredSourceArtifactFormats
        self.requiredSignoffArtifactIDs = requiredSignoffArtifactIDs
        self.requiredStageFamilies = requiredStageFamilies
        self.requireReadyOracleEvidence = requireReadyOracleEvidence
    }
}
