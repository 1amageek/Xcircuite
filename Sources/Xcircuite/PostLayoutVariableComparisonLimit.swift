/// A comparison limit that applies to a single waveform variable.
///
/// A variable-specific limit overrides the global limit for the metric it
/// specifies (absolute or relative delta); metrics it leaves `nil` remain
/// governed by the global limits. Variable names are matched
/// case-insensitively, consistent with waveform variable matching in
/// `PostLayoutComparisonService`.
public struct PostLayoutVariableComparisonLimit: Sendable, Hashable, Codable {
    public var variableName: String
    public var maxAbsoluteDelta: Double?
    public var maxRelativeDelta: Double?

    public init(
        variableName: String,
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil
    ) {
        self.variableName = variableName
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
    }
}
