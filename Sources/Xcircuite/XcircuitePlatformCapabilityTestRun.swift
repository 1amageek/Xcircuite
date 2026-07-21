public struct XcircuitePlatformCapabilityTestRun: Sendable, Hashable {
    public let evidence: XcircuitePlatformCapabilityTestEvidence
    public let verification: XcircuitePlatformCapabilityTestEvidenceVerification

    public init(
        evidence: XcircuitePlatformCapabilityTestEvidence,
        verification: XcircuitePlatformCapabilityTestEvidenceVerification
    ) {
        self.evidence = evidence
        self.verification = verification
    }
}
