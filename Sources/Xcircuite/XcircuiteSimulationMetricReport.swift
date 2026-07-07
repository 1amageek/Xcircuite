import Foundation

public struct XcircuiteSimulationMetricReport: Sendable, Hashable, Codable {
    public struct MeasurementVerdict: Sendable, Hashable, Codable {
        public var name: String
        public var status: String
        public var value: Double?
        public var target: Double
        public var tolerance: Double

        public init(
            name: String,
            status: String,
            value: Double?,
            target: Double,
            tolerance: Double
        ) {
            self.name = name
            self.status = status
            self.value = value
            self.target = target
            self.tolerance = tolerance
        }
    }

    public struct Diagnostic: Sendable, Hashable, Codable {
        public var severity: String
        public var code: String
        public var message: String

        public init(severity: String, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public var schemaVersion: Int
    public var status: String
    public var source: String
    public var sourceReportPath: String?
    public var analysisLabel: String?
    public var expectations: [SimulationMeasurementExpectation]
    public var measurements: [SimulationMeasurementValue]
    public var verdicts: [MeasurementVerdict]
    public var diagnostics: [Diagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        source: String,
        sourceReportPath: String? = nil,
        analysisLabel: String? = nil,
        expectations: [SimulationMeasurementExpectation],
        measurements: [SimulationMeasurementValue],
        verdicts: [MeasurementVerdict],
        diagnostics: [Diagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.source = source
        self.sourceReportPath = sourceReportPath
        self.analysisLabel = analysisLabel
        self.expectations = expectations
        self.measurements = measurements
        self.verdicts = verdicts
        self.diagnostics = diagnostics
    }
}
