public struct XcircuiteSymbolicPlannerSolverFamilyComparisonRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var comparisonID: String
    public var qualificationArtifactIDs: [String]
    public var qualificationPaths: [String]
    public var selectionPolicy: String

    public init(
        schemaVersion: Int = 1,
        runID: String,
        comparisonID: String = "solver-family-1",
        qualificationArtifactIDs: [String] = [],
        qualificationPaths: [String] = [],
        selectionPolicy: String = "prefer-qualified-health-replay-goals-proof-optimality-cost"
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.comparisonID = comparisonID
        self.qualificationArtifactIDs = qualificationArtifactIDs
        self.qualificationPaths = qualificationPaths
        self.selectionPolicy = selectionPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case comparisonID
        case qualificationArtifactIDs
        case qualificationPaths
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
        comparisonID = try container.decodeIfPresent(String.self, forKey: .comparisonID) ?? "solver-family-1"
        qualificationArtifactIDs = try container.decodeIfPresent([String].self, forKey: .qualificationArtifactIDs) ?? []
        qualificationPaths = try container.decodeIfPresent([String].self, forKey: .qualificationPaths) ?? []
        selectionPolicy = try container.decodeIfPresent(String.self, forKey: .selectionPolicy)
            ?? "prefer-qualified-health-replay-goals-proof-optimality-cost"
    }
}
