import Foundation

public struct XcircuiteFlowTechnologyCatalogInventoryItem: Sendable, Hashable, Codable {
    public var catalogPath: String
    public var resolvedCatalogPath: String?
    public var schemaVersion: Int?
    public var entries: [XcircuiteFlowTechnologyCatalogEntryInventory]
    public var status: XcircuiteFlowTechnologyCatalogInventoryStatus
    public var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue]

    public init(
        catalogPath: String,
        resolvedCatalogPath: String? = nil,
        schemaVersion: Int? = nil,
        entries: [XcircuiteFlowTechnologyCatalogEntryInventory] = [],
        status: XcircuiteFlowTechnologyCatalogInventoryStatus,
        issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
    ) {
        self.catalogPath = catalogPath
        self.resolvedCatalogPath = resolvedCatalogPath
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.status = status
        self.issues = issues
    }
}
