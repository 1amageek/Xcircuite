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
            self.testEvidenceDiagnosticCount = testEvidenceDiagnosticCount
        }

        private enum CodingKeys: String, CodingKey {
            case milestoneCount
            case passedCount
            case partialCount
            case failedCount
            case domainCount
            case operationCount
            case implementedOperationCount
            case testEvidenceCount
            case validTestEvidenceCount
            case invalidTestEvidenceCount
            case testEvidenceDiagnosticCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.milestoneCount = try container.decode(Int.self, forKey: .milestoneCount)
            self.passedCount = try container.decode(Int.self, forKey: .passedCount)
            self.partialCount = try container.decode(Int.self, forKey: .partialCount)
            self.failedCount = try container.decode(Int.self, forKey: .failedCount)
            self.domainCount = try container.decode(Int.self, forKey: .domainCount)
            self.operationCount = try container.decode(Int.self, forKey: .operationCount)
            self.implementedOperationCount = try container.decode(Int.self, forKey: .implementedOperationCount)
            self.testEvidenceCount = try container.decode(Int.self, forKey: .testEvidenceCount)
            self.validTestEvidenceCount = try container.decodeIfPresent(
                Int.self,
                forKey: .validTestEvidenceCount
            ) ?? testEvidenceCount
            self.invalidTestEvidenceCount = try container.decodeIfPresent(
                Int.self,
                forKey: .invalidTestEvidenceCount
            ) ?? 0
            self.testEvidenceDiagnosticCount = try container.decodeIfPresent(
                Int.self,
                forKey: .testEvidenceDiagnosticCount
            ) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(milestoneCount, forKey: .milestoneCount)
            try container.encode(passedCount, forKey: .passedCount)
            try container.encode(partialCount, forKey: .partialCount)
            try container.encode(failedCount, forKey: .failedCount)
            try container.encode(domainCount, forKey: .domainCount)
            try container.encode(operationCount, forKey: .operationCount)
            try container.encode(implementedOperationCount, forKey: .implementedOperationCount)
            try container.encode(testEvidenceCount, forKey: .testEvidenceCount)
            try container.encode(validTestEvidenceCount, forKey: .validTestEvidenceCount)
            try container.encode(invalidTestEvidenceCount, forKey: .invalidTestEvidenceCount)
            try container.encode(testEvidenceDiagnosticCount, forKey: .testEvidenceDiagnosticCount)
        }
    }

    public var schemaVersion: Int
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
        schemaVersion: Int = 2,
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
        self.schemaVersion = schemaVersion
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
}
