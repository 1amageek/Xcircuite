public struct SimulationGoldenComparisonOptions: Sendable, Hashable, Codable {
    public var maxAbsoluteDelta: Double?
    public var maxRelativeDelta: Double?
    public var relativeDeltaDenominatorFloor: Double?
    public var requiredVariables: [String]
    public var comparedVariables: [String]
    public var allowInterpolation: Bool

    public init(
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil,
        requiredVariables: [String] = [],
        comparedVariables: [String] = [],
        allowInterpolation: Bool = true
    ) {
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
        self.requiredVariables = requiredVariables
        self.comparedVariables = comparedVariables
        self.allowInterpolation = allowInterpolation
    }

    private enum CodingKeys: String, CodingKey {
        case maxAbsoluteDelta
        case maxRelativeDelta
        case relativeDeltaDenominatorFloor
        case requiredVariables
        case comparedVariables
        case allowInterpolation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxAbsoluteDelta = try container.decodeIfPresent(Double.self, forKey: .maxAbsoluteDelta)
        maxRelativeDelta = try container.decodeIfPresent(Double.self, forKey: .maxRelativeDelta)
        relativeDeltaDenominatorFloor = try container.decodeIfPresent(
            Double.self,
            forKey: .relativeDeltaDenominatorFloor
        )
        requiredVariables = try container.decodeIfPresent([String].self, forKey: .requiredVariables) ?? []
        comparedVariables = try container.decodeIfPresent([String].self, forKey: .comparedVariables) ?? []
        allowInterpolation = try container.decodeIfPresent(Bool.self, forKey: .allowInterpolation) ?? true
    }
}
