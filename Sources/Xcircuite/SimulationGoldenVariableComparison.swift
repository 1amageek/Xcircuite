public struct SimulationGoldenVariableComparison: Sendable, Hashable, Codable {
    public struct WorstPoint: Sendable, Hashable, Codable {
        public var sweepValue: Double
        public var goldenValue: Double
        public var candidateValue: Double
        public var absoluteDelta: Double
        public var relativeDelta: Double

        public init(
            sweepValue: Double,
            goldenValue: Double,
            candidateValue: Double,
            absoluteDelta: Double,
            relativeDelta: Double
        ) {
            self.sweepValue = sweepValue
            self.goldenValue = goldenValue
            self.candidateValue = candidateValue
            self.absoluteDelta = absoluteDelta
            self.relativeDelta = relativeDelta
        }
    }

    public var variableName: String
    public var pointCount: Int
    public var maxAbsoluteDelta: Double
    public var maxRelativeDelta: Double
    public var worstPoint: WorstPoint?

    public init(
        variableName: String,
        pointCount: Int,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        worstPoint: WorstPoint?
    ) {
        self.variableName = variableName
        self.pointCount = pointCount
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.worstPoint = worstPoint
    }
}
