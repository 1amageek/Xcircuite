public struct SimulationGoldenCorpusCaseSpec: Codable, Sendable, Hashable {
    public var caseID: String
    public var description: String?
    public var netlistPath: String
    public var goldenWaveformPath: String
    public var options: SimulationGoldenComparisonOptions
    public var coverageTags: [String]
    public var expectedGateStatus: String
    public var expectedDiagnosticSubstrings: [String]

    public init(
        caseID: String,
        description: String? = nil,
        netlistPath: String,
        goldenWaveformPath: String,
        options: SimulationGoldenComparisonOptions = SimulationGoldenComparisonOptions(),
        coverageTags: [String] = [],
        expectedGateStatus: String = "passed",
        expectedDiagnosticSubstrings: [String] = []
    ) {
        self.caseID = caseID
        self.description = description
        self.netlistPath = netlistPath
        self.goldenWaveformPath = goldenWaveformPath
        self.options = options
        self.coverageTags = coverageTags
        self.expectedGateStatus = expectedGateStatus
        self.expectedDiagnosticSubstrings = expectedDiagnosticSubstrings
    }

    private enum CodingKeys: String, CodingKey {
        case caseID
        case description
        case netlistPath
        case goldenWaveformPath
        case options
        case coverageTags
        case expectedGateStatus
        case expectedDiagnosticSubstrings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try container.decode(String.self, forKey: .caseID)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        netlistPath = try container.decode(String.self, forKey: .netlistPath)
        goldenWaveformPath = try container.decode(String.self, forKey: .goldenWaveformPath)
        options = try container.decodeIfPresent(
            SimulationGoldenComparisonOptions.self,
            forKey: .options
        ) ?? SimulationGoldenComparisonOptions()
        coverageTags = try container.decode([String].self, forKey: .coverageTags)
        expectedGateStatus = try container.decode(String.self, forKey: .expectedGateStatus)
        expectedDiagnosticSubstrings = try container.decodeIfPresent(
            [String].self,
            forKey: .expectedDiagnosticSubstrings
        ) ?? []
    }
}
