import Foundation

public struct OpAmpSimulationMetricExtraction: Sendable, Hashable, Codable {
    public struct UnmappedMeasurement: Sendable, Hashable, Codable {
        public var name: String
        public var value: Double
        public var unit: String

        public init(name: String, value: Double, unit: String) {
            self.name = name
            self.value = value
            self.unit = unit
        }
    }

    public var schemaVersion: Int
    public var sourceKind: String
    public var sourceStatus: String?
    public var sourceAnalysisLabel: String?
    public var observedMetrics: [OpAmpEstimatedMetric]
    public var unmappedMeasurements: [UnmappedMeasurement]
    public var diagnostics: [OpAmpDesignDiagnostic]

    public init(
        schemaVersion: Int = 1,
        sourceKind: String,
        sourceStatus: String? = nil,
        sourceAnalysisLabel: String? = nil,
        observedMetrics: [OpAmpEstimatedMetric],
        unmappedMeasurements: [UnmappedMeasurement],
        diagnostics: [OpAmpDesignDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sourceKind = sourceKind
        self.sourceStatus = sourceStatus
        self.sourceAnalysisLabel = sourceAnalysisLabel
        self.observedMetrics = observedMetrics
        self.unmappedMeasurements = unmappedMeasurements
        self.diagnostics = diagnostics
    }
}
