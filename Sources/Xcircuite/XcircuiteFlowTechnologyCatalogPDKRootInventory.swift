import Foundation

public struct XcircuiteFlowTechnologyCatalogPDKRootInventory: Sendable, Hashable, Codable {
    public var requestedPath: String
    public var resolvedPath: String?
    public var discoveredCatalogPaths: [String]
    public var status: XcircuiteFlowTechnologyCatalogInventoryStatus
    public var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue]

    public init(
        requestedPath: String,
        resolvedPath: String? = nil,
        discoveredCatalogPaths: [String] = [],
        status: XcircuiteFlowTechnologyCatalogInventoryStatus,
        issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
    ) {
        self.requestedPath = requestedPath
        self.resolvedPath = resolvedPath
        self.discoveredCatalogPaths = discoveredCatalogPaths
        self.status = status
        self.issues = issues
    }
}
