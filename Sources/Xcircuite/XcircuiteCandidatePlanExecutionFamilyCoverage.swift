public struct XcircuiteCandidatePlanExecutionFamilyCoverage: Codable, Sendable, Hashable {
    public var familyID: String
    public var status: String
    public var stepIDs: [String]
    public var domainIDs: [String]
    public var operationIDs: [String]
    public var artifactIDs: [String]

    public init(
        familyID: String,
        status: String,
        stepIDs: [String],
        domainIDs: [String],
        operationIDs: [String],
        artifactIDs: [String]
    ) {
        self.familyID = familyID
        self.status = status
        self.stepIDs = stepIDs
        self.domainIDs = domainIDs
        self.operationIDs = operationIDs
        self.artifactIDs = artifactIDs
    }
}
