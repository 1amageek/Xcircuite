public struct XcircuitePlatformCapabilityReadinessReport: Codable, Sendable, Hashable {
    public struct Summary: Codable, Sendable, Hashable {
        public var milestoneCount: Int
        public var passedCount: Int
        public var partialCount: Int
        public var failedCount: Int
        public var domainCount: Int
        public var operationCount: Int
        public var implementedOperationCount: Int
        public var testEvidenceCount: Int
        public var validTestEvidenceCount: Int
        public var invalidTestEvidenceCount: Int
        public var passedTestEvidenceCount: Int
        public var unverifiedTestEvidenceCount: Int
        public var failedTestEvidenceCount: Int
        public var testEvidenceDiagnosticCount: Int

        public init(
            milestoneCount: Int,
            passedCount: Int,
            partialCount: Int,
            failedCount: Int,
            domainCount: Int,
            operationCount: Int,
            implementedOperationCount: Int,
            testEvidenceCount: Int,
            validTestEvidenceCount: Int? = nil,
            invalidTestEvidenceCount: Int = 0,
            passedTestEvidenceCount: Int? = nil,
            unverifiedTestEvidenceCount: Int? = nil,
            failedTestEvidenceCount: Int = 0,
            testEvidenceDiagnosticCount: Int = 0
        ) {
            self.milestoneCount = milestoneCount
            self.passedCount = passedCount
            self.partialCount = partialCount
            self.failedCount = failedCount
            self.domainCount = domainCount
            self.operationCount = operationCount
            self.implementedOperationCount = implementedOperationCount
            self.testEvidenceCount = testEvidenceCount
            self.validTestEvidenceCount = validTestEvidenceCount ?? testEvidenceCount
            self.invalidTestEvidenceCount = invalidTestEvidenceCount
            self.passedTestEvidenceCount = passedTestEvidenceCount ?? 0
            self.unverifiedTestEvidenceCount = unverifiedTestEvidenceCount
                ?? max(0, testEvidenceCount - self.passedTestEvidenceCount - failedTestEvidenceCount)
            self.failedTestEvidenceCount = failedTestEvidenceCount
            self.testEvidenceDiagnosticCount = testEvidenceDiagnosticCount
        }

    }

    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public var reportID: String
    public var status: XcircuitePlatformCapabilityReadinessStatus
    public var actionDomainRunID: String
    public var actionDomainGeneratedAt: String
    public var summary: Summary
    public var milestones: [XcircuitePlatformCapabilityMilestoneReadiness]
    public var testEvidence: [XcircuitePlatformCapabilityTestEvidence]
    public var diagnostics: [XcircuitePlatformCapabilityDiagnostic]
    public var nextActions: [String]

    public init(
        reportID: String = "xcircuite-platform-capability-readiness",
        status: XcircuitePlatformCapabilityReadinessStatus,
        actionDomainRunID: String,
        actionDomainGeneratedAt: String,
        summary: Summary,
        milestones: [XcircuitePlatformCapabilityMilestoneReadiness],
        testEvidence: [XcircuitePlatformCapabilityTestEvidence],
        diagnostics: [XcircuitePlatformCapabilityDiagnostic],
        nextActions: [String]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.reportID = reportID
        self.status = status
        self.actionDomainRunID = actionDomainRunID
        self.actionDomainGeneratedAt = actionDomainGeneratedAt
        self.summary = summary
        self.milestones = milestones
        self.testEvidence = testEvidence
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reportID
        case status
        case actionDomainRunID
        case actionDomainGeneratedAt
        case summary
        case milestones
        case testEvidence
        case diagnostics
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected platform capability readiness schema version \(Self.currentSchemaVersion)."
            )
        }
        reportID = try container.decode(String.self, forKey: .reportID)
        status = try container.decode(XcircuitePlatformCapabilityReadinessStatus.self, forKey: .status)
        actionDomainRunID = try container.decode(String.self, forKey: .actionDomainRunID)
        actionDomainGeneratedAt = try container.decode(String.self, forKey: .actionDomainGeneratedAt)
        summary = try container.decode(Summary.self, forKey: .summary)
        milestones = try container.decode(
            [XcircuitePlatformCapabilityMilestoneReadiness].self,
            forKey: .milestones
        )
        testEvidence = try container.decode([XcircuitePlatformCapabilityTestEvidence].self, forKey: .testEvidence)
        diagnostics = try container.decode([XcircuitePlatformCapabilityDiagnostic].self, forKey: .diagnostics)
        nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(reportID, forKey: .reportID)
        try container.encode(status, forKey: .status)
        try container.encode(actionDomainRunID, forKey: .actionDomainRunID)
        try container.encode(actionDomainGeneratedAt, forKey: .actionDomainGeneratedAt)
        try container.encode(summary, forKey: .summary)
        try container.encode(milestones, forKey: .milestones)
        try container.encode(testEvidence, forKey: .testEvidence)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
