public struct XcircuiteSymbolicPlannerSolverFamilyPromotionRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var comparisonID: String
    public var comparisonArtifactID: String?
    public var comparisonPath: String?
    public var selectedCandidateIndex: Int?
    public var requireQualified: Bool
    public var verifyPromotedPlan: Bool

    public init(
        schemaVersion: Int = 1,
        runID: String,
        comparisonID: String = "solver-family-1",
        comparisonArtifactID: String? = nil,
        comparisonPath: String? = nil,
        selectedCandidateIndex: Int? = nil,
        requireQualified: Bool = true,
        verifyPromotedPlan: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.comparisonID = comparisonID
        self.comparisonArtifactID = comparisonArtifactID
        self.comparisonPath = comparisonPath
        self.selectedCandidateIndex = selectedCandidateIndex
        self.requireQualified = requireQualified
        self.verifyPromotedPlan = verifyPromotedPlan
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case comparisonID
        case comparisonArtifactID
        case comparisonPath
        case selectedCandidateIndex
        case requireQualified
        case verifyPromotedPlan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported solver family promotion request schema version: \(schemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        comparisonID = try container.decode(String.self, forKey: .comparisonID)
        comparisonArtifactID = try container.decodeIfPresent(String.self, forKey: .comparisonArtifactID)
        comparisonPath = try container.decodeIfPresent(String.self, forKey: .comparisonPath)
        selectedCandidateIndex = try container.decodeIfPresent(Int.self, forKey: .selectedCandidateIndex)
        requireQualified = try container.decode(Bool.self, forKey: .requireQualified)
        verifyPromotedPlan = try container.decode(Bool.self, forKey: .verifyPromotedPlan)
    }
}
