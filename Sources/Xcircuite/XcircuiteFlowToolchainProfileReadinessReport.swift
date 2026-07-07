public struct XcircuiteFlowToolchainProfileReadinessReport: Sendable, Hashable, Codable {
    public var profileID: String?
    public var pdkID: String?
    public var technologyCatalogID: String?
    public var technologyCatalogPath: String?
    public var status: XcircuiteFlowToolchainProfileReadinessStatus
    public var issues: [XcircuiteFlowToolchainProfileReadinessIssue]

    public init(
        profileID: String?,
        pdkID: String?,
        technologyCatalogID: String?,
        technologyCatalogPath: String?,
        status: XcircuiteFlowToolchainProfileReadinessStatus,
        issues: [XcircuiteFlowToolchainProfileReadinessIssue] = []
    ) {
        self.profileID = profileID
        self.pdkID = pdkID
        self.technologyCatalogID = technologyCatalogID
        self.technologyCatalogPath = technologyCatalogPath
        self.status = status
        self.issues = issues
    }
}
