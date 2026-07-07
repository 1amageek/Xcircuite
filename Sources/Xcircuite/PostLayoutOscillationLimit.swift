public struct PostLayoutOscillationLimit: Sendable, Hashable, Codable {
    public var variableName: String
    public var minimumPostAmplitude: Double?
    public var minimumPostTransitionCount: Int?
    public var maximumFrequencyRelativeDelta: Double?

    public init(
        variableName: String,
        minimumPostAmplitude: Double? = nil,
        minimumPostTransitionCount: Int? = nil,
        maximumFrequencyRelativeDelta: Double? = nil
    ) {
        self.variableName = variableName
        self.minimumPostAmplitude = minimumPostAmplitude
        self.minimumPostTransitionCount = minimumPostTransitionCount
        self.maximumFrequencyRelativeDelta = maximumFrequencyRelativeDelta
    }
}
