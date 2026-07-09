import Foundation

public struct OpAmpPostLayoutComparisonReport: Sendable, Hashable, Codable {
    public struct MetricDelta: Sendable, Hashable, Codable {
        public var metricID: OpAmpMetricID
        public var preLayoutValue: Double?
        public var postLayoutValue: Double?
        public var delta: Double?
        public var relativeDelta: Double?
        public var unit: String
        public var status: String
        public var classification: String

        public init(
            metricID: OpAmpMetricID,
            preLayoutValue: Double?,
            postLayoutValue: Double?,
            delta: Double?,
            relativeDelta: Double?,
            unit: String,
            status: String,
            classification: String
        ) {
            self.metricID = metricID
            self.preLayoutValue = preLayoutValue
            self.postLayoutValue = postLayoutValue
            self.delta = delta
            self.relativeDelta = relativeDelta
            self.unit = unit
            self.status = status
            self.classification = classification
        }
    }

    public var schemaVersion: Int
    public var reportID: String
    public var specID: String
    public var status: String
    public var deltas: [MetricDelta]
    public var diagnostics: [OpAmpDesignDiagnostic]
    public var suggestedActions: [String]

    public init(
        schemaVersion: Int = 1,
        reportID: String,
        specID: String,
        status: String,
        deltas: [MetricDelta],
        diagnostics: [OpAmpDesignDiagnostic] = [],
        suggestedActions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.reportID = reportID
        self.specID = specID
        self.status = status
        self.deltas = deltas
        self.diagnostics = diagnostics
        self.suggestedActions = suggestedActions
    }
}
