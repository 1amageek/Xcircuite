public struct XcircuiteActionDomain: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var domainID: String
    public var ownerPackages: [String]
    public var operations: [XcircuiteActionDomainOperation]

    public init(
        schemaVersion: Int = 1,
        domainID: String,
        ownerPackages: [String],
        operations: [XcircuiteActionDomainOperation]
    ) {
        self.schemaVersion = schemaVersion
        self.domainID = domainID
        self.ownerPackages = ownerPackages
        self.operations = operations
    }
}
