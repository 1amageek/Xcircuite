public struct XcircuitePlatformCapabilityRequirementCoverage: Codable, Sendable, Hashable {
    public var required: [String]
    public var present: [String]
    public var missing: [String]

    public init(required: [String], present: [String], missing: [String]) {
        self.required = required
        self.present = present
        self.missing = missing
    }
}
