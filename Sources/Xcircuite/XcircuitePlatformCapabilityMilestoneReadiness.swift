public struct XcircuitePlatformCapabilityMilestoneReadiness: Codable, Sendable, Hashable {
    public var milestoneID: String
    public var title: String
    public var status: XcircuitePlatformCapabilityReadinessStatus
    public var requiredDomains: XcircuitePlatformCapabilityRequirementCoverage
    public var requiredOperations: XcircuitePlatformCapabilityRequirementCoverage
    public var requiredArtifacts: XcircuitePlatformCapabilityRequirementCoverage
    public var requiredVerificationGates: XcircuitePlatformCapabilityRequirementCoverage
    public var requiredTestEvidence: XcircuitePlatformCapabilityRequirementCoverage
    public var plannedOperations: [String]
    public var partialOperations: [String]
    public var diagnostics: [XcircuitePlatformCapabilityDiagnostic]
    public var nextActions: [String]

    public init(
        milestoneID: String,
        title: String,
        status: XcircuitePlatformCapabilityReadinessStatus,
        requiredDomains: XcircuitePlatformCapabilityRequirementCoverage,
        requiredOperations: XcircuitePlatformCapabilityRequirementCoverage,
        requiredArtifacts: XcircuitePlatformCapabilityRequirementCoverage,
        requiredVerificationGates: XcircuitePlatformCapabilityRequirementCoverage,
        requiredTestEvidence: XcircuitePlatformCapabilityRequirementCoverage,
        plannedOperations: [String],
        partialOperations: [String],
        diagnostics: [XcircuitePlatformCapabilityDiagnostic],
        nextActions: [String]
    ) {
        self.milestoneID = milestoneID
        self.title = title
        self.status = status
        self.requiredDomains = requiredDomains
        self.requiredOperations = requiredOperations
        self.requiredArtifacts = requiredArtifacts
        self.requiredVerificationGates = requiredVerificationGates
        self.requiredTestEvidence = requiredTestEvidence
        self.plannedOperations = plannedOperations
        self.partialOperations = partialOperations
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
