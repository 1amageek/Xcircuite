public struct PostLayoutOscillationMetric: Sendable, Hashable, Codable {
    public var amplitude: Double
    public var frequency: Double?
    public var averagePeriod: Double?
    public var transitionCount: Int
    public var dutyCycle: Double?

    public init(
        amplitude: Double,
        frequency: Double?,
        averagePeriod: Double?,
        transitionCount: Int,
        dutyCycle: Double?
    ) {
        self.amplitude = amplitude
        self.frequency = frequency
        self.averagePeriod = averagePeriod
        self.transitionCount = transitionCount
        self.dutyCycle = dutyCycle
    }
}
