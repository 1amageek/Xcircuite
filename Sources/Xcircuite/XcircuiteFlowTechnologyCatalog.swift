import Foundation

public struct XcircuiteFlowTechnologyCatalog: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var entries: [XcircuiteFlowTechnologyCatalogEntry]

    public init(
        schemaVersion: Int = 1,
        entries: [XcircuiteFlowTechnologyCatalogEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}
