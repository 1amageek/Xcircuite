public struct XcircuiteSymbolicPlannerSolverFamilyComparisonRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var comparisonID: String
    public var validationArtifactIDs: [String]
    public var validationPaths: [String]
    public var selectionPolicy: String

    public init(
        schemaVersion: Int = 1,
        runID: String,
        comparisonID: String = "solver-family-1",
        validationArtifactIDs: [String] = [],
        validationPaths: [String] = [],
        selectionPolicy: String = "prefer-passing-validation-replay-goals-proof-optimality-cost"
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.comparisonID = comparisonID
        self.validationArtifactIDs = validationArtifactIDs
        self.validationPaths = validationPaths
        self.selectionPolicy = selectionPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case comparisonID
        case validationArtifactIDs
        case validationPaths
        case selectionPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported solver family comparison request schema version: \(schemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        comparisonID = try container.decode(String.self, forKey: .comparisonID)
        validationArtifactIDs = try container.decode([String].self, forKey: .validationArtifactIDs)
        validationPaths = try container.decode([String].self, forKey: .validationPaths)
        selectionPolicy = try container.decodeIfPresent(String.self, forKey: .selectionPolicy)
            ?? "prefer-passing-validation-replay-goals-proof-optimality-cost"
    }
}
