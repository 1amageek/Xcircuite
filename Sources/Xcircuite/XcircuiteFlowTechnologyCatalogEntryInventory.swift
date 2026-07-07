import Foundation

public struct XcircuiteFlowTechnologyCatalogEntryInventory: Sendable, Hashable, Codable {
    public var technologyCatalogID: String
    public var pdkID: String
    public var profileIDs: [String]
    public var requiredFiles: [XcircuiteFlowTechnologyCatalogRequiredFileInventory]
    public var metadata: [String: String]?
    public var status: XcircuiteFlowTechnologyCatalogInventoryStatus
    public var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue]

    public init(
        technologyCatalogID: String,
        pdkID: String,
        profileIDs: [String] = [],
        requiredFiles: [XcircuiteFlowTechnologyCatalogRequiredFileInventory] = [],
        metadata: [String: String]? = nil,
        status: XcircuiteFlowTechnologyCatalogInventoryStatus,
        issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
    ) {
        self.technologyCatalogID = technologyCatalogID
        self.pdkID = pdkID
        self.profileIDs = profileIDs
        self.requiredFiles = requiredFiles
        self.metadata = metadata
        self.status = status
        self.issues = issues
    }
}
