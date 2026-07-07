public struct XcircuiteSymbolicPlannerPDDLAtomMapping: Codable, Sendable, Hashable {
    public var atom: String
    public var predicate: String
    public var roles: [String]

    public init(
        atom: String,
        predicate: String,
        roles: [String]
    ) {
        self.atom = atom
        self.predicate = predicate
        self.roles = roles
    }
}
