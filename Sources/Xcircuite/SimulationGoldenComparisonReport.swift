public struct SimulationGoldenComparisonReport: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var status: String
    public var goldenPointCount: Int
    public var candidatePointCount: Int
    public var sweepVariable: String?
    public var comparedPointCount: Int
    public var usesInterpolation: Bool
    public var maxAbsoluteDelta: Double
    public var maxRelativeDelta: Double
    public var comparedVariables: [SimulationGoldenVariableComparison]
    public var requiredVariables: [SimulationGoldenRequiredVariableResult]
    public var missingInCandidate: [String]
    public var addedInCandidate: [String]
    public var diagnostics: [String]
    public var gateStatus: String
    public var gateViolations: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        goldenPointCount: Int,
        candidatePointCount: Int,
        sweepVariable: String?,
        comparedPointCount: Int,
        usesInterpolation: Bool,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        comparedVariables: [SimulationGoldenVariableComparison],
        requiredVariables: [SimulationGoldenRequiredVariableResult],
        missingInCandidate: [String],
        addedInCandidate: [String],
        diagnostics: [String],
        gateStatus: String,
        gateViolations: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.goldenPointCount = goldenPointCount
        self.candidatePointCount = candidatePointCount
        self.sweepVariable = sweepVariable
        self.comparedPointCount = comparedPointCount
        self.usesInterpolation = usesInterpolation
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.comparedVariables = comparedVariables
        self.requiredVariables = requiredVariables
        self.missingInCandidate = missingInCandidate
        self.addedInCandidate = addedInCandidate
        self.diagnostics = diagnostics
        self.gateStatus = gateStatus
        self.gateViolations = gateViolations
    }
}
