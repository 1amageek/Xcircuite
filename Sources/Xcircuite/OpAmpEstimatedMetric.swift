import Foundation

public struct OpAmpEstimatedMetric: Sendable, Hashable, Codable {
    public var metricID: OpAmpMetricID
    public var value: Double
    public var unit: String
    public var method: String

    public init(
        metricID: OpAmpMetricID,
        value: Double,
        unit: String,
        method: String
    ) {
        self.metricID = metricID
        self.value = value
        self.unit = unit
        self.method = method
    }
}
