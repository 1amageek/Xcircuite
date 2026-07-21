public struct XcircuiteSymbolicPlannerFeature: Codable, Sendable, Hashable {
    public var coverageTag: String
    public var category: String
    public var capability: String
    public var maturity: XcircuiteOperationMaturity
    public var requiredForCorpusTrust: Bool
    public var evidence: [String]
    public var remainingWork: [String]

    public init(
        coverageTag: String,
        category: String,
        capability: String,
        maturity: XcircuiteOperationMaturity,
        requiredForCorpusTrust: Bool,
        evidence: [String] = [],
        remainingWork: [String] = []
    ) {
        self.coverageTag = coverageTag
        self.category = category
        self.capability = capability
        self.maturity = maturity
        self.requiredForCorpusTrust = requiredForCorpusTrust
        self.evidence = evidence
        self.remainingWork = remainingWork
    }
}
