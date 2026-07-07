import Foundation

public struct XcircuiteFlowTechnologyCatalogInventoryIssue: Sendable, Hashable, Codable {
    public var code: String
    public var field: String
    public var message: String

    public init(
        code: String,
        field: String,
        message: String
    ) {
        self.code = code
        self.field = field
        self.message = message
    }
}
