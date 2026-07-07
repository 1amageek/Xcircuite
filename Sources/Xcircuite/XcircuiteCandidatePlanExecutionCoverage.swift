public struct XcircuiteCandidatePlanExecutionCoverage: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var requiredFamilyIDs: [String]
    public var coveredFamilyIDs: [String]
    public var missingFamilyIDs: [String]
    public var familyCoverage: [XcircuiteCandidatePlanExecutionFamilyCoverage]
    public var producedArtifactIDs: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        requiredFamilyIDs: [String],
        coveredFamilyIDs: [String],
        missingFamilyIDs: [String],
        familyCoverage: [XcircuiteCandidatePlanExecutionFamilyCoverage],
        producedArtifactIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.requiredFamilyIDs = requiredFamilyIDs
        self.coveredFamilyIDs = coveredFamilyIDs
        self.missingFamilyIDs = missingFamilyIDs
        self.familyCoverage = familyCoverage
        self.producedArtifactIDs = producedArtifactIDs
    }
}
