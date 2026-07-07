public struct XcircuiteSymbolicPlannerSolverCertificateClaim: Codable, Sendable, Hashable {
    public var claimID: String
    public var kind: String
    public var status: String
    public var value: String?
    public var numericValue: Double?
    public var unit: String?
    public var evidenceLine: String?

    private enum CodingKeys: String, CodingKey {
        case claimID
        case kind
        case status
        case value
        case numericValue
        case unit
        case evidenceLine
    }

    public init(
        claimID: String,
        kind: String,
        status: String,
        value: String? = nil,
        numericValue: Double? = nil,
        unit: String? = nil,
        evidenceLine: String? = nil
    ) {
        self.claimID = claimID
        self.kind = kind
        self.status = status
        self.value = value
        self.numericValue = numericValue
        self.unit = unit
        self.evidenceLine = evidenceLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            claimID: try container.decodeIfPresent(String.self, forKey: .claimID) ?? "claim",
            kind: try container.decode(String.self, forKey: .kind),
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? "claimed",
            value: try container.decodeIfPresent(String.self, forKey: .value),
            numericValue: try container.decodeIfPresent(Double.self, forKey: .numericValue),
            unit: try container.decodeIfPresent(String.self, forKey: .unit),
            evidenceLine: try container.decodeIfPresent(String.self, forKey: .evidenceLine)
        )
    }
}
