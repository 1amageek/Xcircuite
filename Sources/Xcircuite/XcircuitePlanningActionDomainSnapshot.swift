public struct XcircuitePlanningActionDomainSnapshot: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var generatedAt: String
    public var domains: [XcircuiteActionDomain]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        generatedAt: String,
        domains: [XcircuiteActionDomain]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.generatedAt = generatedAt
        self.domains = domains
    }
}
