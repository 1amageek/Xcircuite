import Foundation

public struct XcircuiteFlowTechnologyCatalogEntry: Sendable, Hashable, Codable {
    public var technologyCatalogID: String
    public var pdkID: String
    public var profileIDs: [String]?
    public var requiredFiles: [XcircuiteFlowTechnologyCatalogRequiredFile]?
    public var metadata: [String: String]?

    public init(
        technologyCatalogID: String,
        pdkID: String,
        profileIDs: [String]? = nil,
        requiredFiles: [XcircuiteFlowTechnologyCatalogRequiredFile]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.technologyCatalogID = technologyCatalogID
        self.pdkID = pdkID
        self.profileIDs = profileIDs
        self.requiredFiles = requiredFiles
        self.metadata = metadata
    }
}
