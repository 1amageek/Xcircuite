public struct PostLayoutComparisonReport: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var status: String
    public var preLayoutPointCount: Int
    public var postLayoutPointCount: Int
    public var sweepVariable: String?
    public var comparedPointCount: Int
    public var maxAbsoluteDelta: Double
    public var maxRelativeDelta: Double
    public var comparedVariables: [PostLayoutVariableComparison]
    public var requiredPostVariables: [PostLayoutRequiredVariableResult]
    public var oscillationMetrics: [PostLayoutOscillationMetricComparison]
    public var missingInPostLayout: [String]
    public var addedInPostLayout: [String]
    public var diagnostics: [String]
    public var gateStatus: String
    public var gateViolations: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        preLayoutPointCount: Int,
        postLayoutPointCount: Int,
        sweepVariable: String?,
        comparedPointCount: Int,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        comparedVariables: [PostLayoutVariableComparison],
        requiredPostVariables: [PostLayoutRequiredVariableResult],
        oscillationMetrics: [PostLayoutOscillationMetricComparison],
        missingInPostLayout: [String],
        addedInPostLayout: [String],
        diagnostics: [String],
        gateStatus: String,
        gateViolations: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.preLayoutPointCount = preLayoutPointCount
        self.postLayoutPointCount = postLayoutPointCount
        self.sweepVariable = sweepVariable
        self.comparedPointCount = comparedPointCount
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.comparedVariables = comparedVariables
        self.requiredPostVariables = requiredPostVariables
        self.oscillationMetrics = oscillationMetrics
        self.missingInPostLayout = missingInPostLayout
        self.addedInPostLayout = addedInPostLayout
        self.diagnostics = diagnostics
        self.gateStatus = gateStatus
        self.gateViolations = gateViolations
    }
}
