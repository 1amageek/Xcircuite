import Foundation

public struct XcircuiteFlowTechnologyCatalogRequiredFileInventory: Sendable, Hashable, Codable {
    public var purpose: String
    public var path: String
    public var resolvedPath: String?
    public var resolutionSource: String?
    public var exists: Bool
    public var isDirectory: Bool
    public var status: XcircuiteFlowTechnologyCatalogInventoryStatus
    public var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue]

    public init(
        purpose: String,
        path: String,
        resolvedPath: String? = nil,
        resolutionSource: String? = nil,
        exists: Bool,
        isDirectory: Bool,
        status: XcircuiteFlowTechnologyCatalogInventoryStatus,
        issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
    ) {
        self.purpose = purpose
        self.path = path
        self.resolvedPath = resolvedPath
        self.resolutionSource = resolutionSource
        self.exists = exists
        self.isDirectory = isDirectory
        self.status = status
        self.issues = issues
    }
}
