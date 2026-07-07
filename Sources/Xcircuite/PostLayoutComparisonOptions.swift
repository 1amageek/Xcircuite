public struct PostLayoutComparisonOptions: Sendable, Hashable, Codable {
    public var maxAbsoluteDelta: Double?
    public var maxRelativeDelta: Double?
    public var relativeDeltaDenominatorFloor: Double?
    public var requiredPostVariables: [String]
    public var oscillationLimits: [PostLayoutOscillationLimit]
    public var variableLimits: [PostLayoutVariableComparisonLimit]

    public init(
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil,
        requiredPostVariables: [String] = [],
        oscillationLimits: [PostLayoutOscillationLimit] = [],
        variableLimits: [PostLayoutVariableComparisonLimit] = []
    ) {
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
        self.requiredPostVariables = requiredPostVariables
        self.oscillationLimits = oscillationLimits
        self.variableLimits = variableLimits
    }

    private enum CodingKeys: String, CodingKey {
        case maxAbsoluteDelta
        case maxRelativeDelta
        case relativeDeltaDenominatorFloor
        case requiredPostVariables
        case oscillationLimits
        case variableLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxAbsoluteDelta = try container.decodeIfPresent(Double.self, forKey: .maxAbsoluteDelta)
        maxRelativeDelta = try container.decodeIfPresent(Double.self, forKey: .maxRelativeDelta)
        relativeDeltaDenominatorFloor = try container.decodeIfPresent(
            Double.self,
            forKey: .relativeDeltaDenominatorFloor
        )
        requiredPostVariables = try container.decodeIfPresent(
            [String].self,
            forKey: .requiredPostVariables
        ) ?? []
        oscillationLimits = try container.decodeIfPresent(
            [PostLayoutOscillationLimit].self,
            forKey: .oscillationLimits
        ) ?? []
        // Backward-compatible decode: runtime.json files written before
        // variable-specific limits existed do not carry this key.
        variableLimits = try container.decodeIfPresent(
            [PostLayoutVariableComparisonLimit].self,
            forKey: .variableLimits
        ) ?? []
    }
}
