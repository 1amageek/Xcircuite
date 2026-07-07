import Foundation

public struct XcircuiteFlowTechnologyCatalogInventory: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var projectRootPath: String?
    public var pdkRoots: [XcircuiteFlowTechnologyCatalogPDKRootInventory]
    public var discoveredCatalogCount: Int
    public var catalogCount: Int
    public var entryCount: Int
    public var failedPDKRootCount: Int
    public var failedCatalogCount: Int
    public var failedEntryCount: Int
    public var missingRequiredFileCount: Int
    public var catalogs: [XcircuiteFlowTechnologyCatalogInventoryItem]
    public var status: XcircuiteFlowTechnologyCatalogInventoryStatus
    public var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue]

    public init(
        schemaVersion: Int = 1,
        projectRootPath: String? = nil,
        pdkRoots: [XcircuiteFlowTechnologyCatalogPDKRootInventory] = [],
        discoveredCatalogCount: Int = 0,
        catalogCount: Int,
        entryCount: Int,
        failedPDKRootCount: Int = 0,
        failedCatalogCount: Int,
        failedEntryCount: Int,
        missingRequiredFileCount: Int,
        catalogs: [XcircuiteFlowTechnologyCatalogInventoryItem],
        status: XcircuiteFlowTechnologyCatalogInventoryStatus,
        issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projectRootPath = projectRootPath
        self.pdkRoots = pdkRoots
        self.discoveredCatalogCount = discoveredCatalogCount
        self.catalogCount = catalogCount
        self.entryCount = entryCount
        self.failedPDKRootCount = failedPDKRootCount
        self.failedCatalogCount = failedCatalogCount
        self.failedEntryCount = failedEntryCount
        self.missingRequiredFileCount = missingRequiredFileCount
        self.catalogs = catalogs
        self.status = status
        self.issues = issues
    }
}
