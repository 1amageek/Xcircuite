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

    private enum CodingKeys: String, CodingKey {
        case evidenceID
        case packagePath
        case command
        case testFilter
        case executionStatus
        case coveredMilestoneIDs
        case coveredRequirementKinds
        case evidenceArtifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.evidenceID = try container.decode(String.self, forKey: .evidenceID)
        self.packagePath = try container.decode(String.self, forKey: .packagePath)
        self.command = try container.decode([String].self, forKey: .command)
        self.testFilter = try container.decode(String.self, forKey: .testFilter)
        self.executionStatus = try container.decodeIfPresent(
            XcircuitePlatformCapabilityTestEvidenceExecutionStatus.self,
            forKey: .executionStatus
        ) ?? .unverified
        self.coveredMilestoneIDs = try container.decode([String].self, forKey: .coveredMilestoneIDs)
        self.coveredRequirementKinds = try container.decode([String].self, forKey: .coveredRequirementKinds)
        self.evidenceArtifacts = try container.decode([String].self, forKey: .evidenceArtifacts)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceID, forKey: .evidenceID)
        try container.encode(packagePath, forKey: .packagePath)
        try container.encode(command, forKey: .command)
        try container.encode(testFilter, forKey: .testFilter)
        try container.encode(executionStatus, forKey: .executionStatus)
        try container.encode(coveredMilestoneIDs, forKey: .coveredMilestoneIDs)
        try container.encode(coveredRequirementKinds, forKey: .coveredRequirementKinds)
        try container.encode(evidenceArtifacts, forKey: .evidenceArtifacts)
    }
}
