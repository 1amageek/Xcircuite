public struct XcircuitePlatformCapabilityTestEvidence: Codable, Sendable, Hashable {
    public var evidenceID: String
    public var packagePath: String
    public var command: [String]
    public var testFilter: String
    public var executionStatus: XcircuitePlatformCapabilityTestEvidenceExecutionStatus
    public var coveredMilestoneIDs: [String]
    public var coveredRequirementKinds: [String]
    public var evidenceArtifacts: [String]

    public init(
        evidenceID: String,
        packagePath: String,
        command: [String],
        testFilter: String,
        executionStatus: XcircuitePlatformCapabilityTestEvidenceExecutionStatus = .unverified,
        coveredMilestoneIDs: [String],
        coveredRequirementKinds: [String],
        evidenceArtifacts: [String]
    ) {
        self.evidenceID = evidenceID
        self.packagePath = packagePath
        self.command = command
        self.testFilter = testFilter
        self.executionStatus = executionStatus
        self.coveredMilestoneIDs = coveredMilestoneIDs
        self.coveredRequirementKinds = coveredRequirementKinds
        self.evidenceArtifacts = evidenceArtifacts
    }

}
