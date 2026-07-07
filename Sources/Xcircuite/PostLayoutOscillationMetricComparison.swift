public struct PostLayoutOscillationMetricComparison: Sendable, Hashable, Codable {
    public var variableName: String
    public var preLayout: PostLayoutOscillationMetric?
    public var postLayout: PostLayoutOscillationMetric?
    public var frequencyRelativeDelta: Double?
    public var violations: [String]

    public init(
        variableName: String,
        preLayout: PostLayoutOscillationMetric?,
        postLayout: PostLayoutOscillationMetric?,
        frequencyRelativeDelta: Double?,
        violations: [String]
    ) {
        self.variableName = variableName
        self.preLayout = preLayout
        self.postLayout = postLayout
        self.frequencyRelativeDelta = frequencyRelativeDelta
        self.violations = violations
    }
}
