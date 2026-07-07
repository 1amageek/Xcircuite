public struct PostLayoutVariableComparison: Sendable, Hashable, Codable {
    public var variableName: String
    public var pointCount: Int
    public var maxAbsoluteDelta: Double
    public var maxRelativeDelta: Double

    public init(
        variableName: String,
        pointCount: Int,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double
    ) {
        self.variableName = variableName
        self.pointCount = pointCount
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
    }
}
