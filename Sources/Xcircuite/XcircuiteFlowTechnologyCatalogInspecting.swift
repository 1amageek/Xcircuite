import Foundation

public protocol XcircuiteFlowTechnologyCatalogInspecting: Sendable {
    func inspect(
        request: XcircuiteFlowTechnologyCatalogInventoryRequest
    ) -> XcircuiteFlowTechnologyCatalogInventory
}
