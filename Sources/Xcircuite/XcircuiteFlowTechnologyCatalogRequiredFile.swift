import Foundation

public struct XcircuiteFlowTechnologyCatalogRequiredFile: Sendable, Hashable, Codable {
    public var purpose: String
    public var path: String
    public var description: String?

    public init(
        purpose: String,
        path: String,
        description: String? = nil
    ) {
        self.purpose = purpose
        self.path = path
        self.description = description
    }
}
