import Foundation

public struct XcircuiteFlowTechnologyCatalogInventoryRequest: Sendable, Hashable {
    public var catalogPaths: [String]
    public var pdkRootPaths: [String]
    public var projectRoot: URL?
    public var maximumCatalogDiscoveryDepth: Int

    public init(
        catalogPaths: [String],
        pdkRootPaths: [String] = [],
        projectRoot: URL? = nil,
        maximumCatalogDiscoveryDepth: Int = 4
    ) {
        self.catalogPaths = catalogPaths
        self.pdkRootPaths = pdkRootPaths
        self.projectRoot = projectRoot
        self.maximumCatalogDiscoveryDepth = maximumCatalogDiscoveryDepth
    }
}
