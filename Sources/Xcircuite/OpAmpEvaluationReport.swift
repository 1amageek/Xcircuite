import Foundation

public struct OpAmpEvaluationReport: Sendable, Hashable, Codable {
    public struct RequirementResult: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case passed
            case failed
            case missing
            case inconclusive
        }

        public var metricID: OpAmpMetricID
        public var status: Status
        public var requiredRelation: OpAmpSpec.Requirement.Relation
        public var targetValue: Double
        public var upperValue: Double?
        public var observedValue: Double?
        public var residual: Double?
        public var unit: String
        public var sourceChannelIDs: [String]
        public var failureClassifications: [String]
        public var suggestedActions: [String]

        public init(
            metricID: OpAmpMetricID,
            status: Status,
            requiredRelation: OpAmpSpec.Requirement.Relation,
            targetValue: Double,
            upperValue: Double? = nil,
            observedValue: Double? = nil,
            residual: Double? = nil,
            unit: String,
            sourceChannelIDs: [String] = [],
            failureClassifications: [String] = [],
            suggestedActions: [String] = []
        ) {
            self.metricID = metricID
            self.status = status
            self.requiredRelation = requiredRelation
            self.targetValue = targetValue
            self.upperValue = upperValue
            self.observedValue = observedValue
            self.residual = residual
            self.unit = unit
            self.sourceChannelIDs = sourceChannelIDs
            self.failureClassifications = failureClassifications
            self.suggestedActions = suggestedActions
        }
    }

    public var schemaVersion: Int
    public var reportID: String
    public var specID: String
    public var status: String
    public var requirementResults: [RequirementResult]
    public var observedMetrics: [OpAmpEstimatedMetric]
    public var diagnostics: [OpAmpDesignDiagnostic]

    public init(
        schemaVersion: Int = 1,
        reportID: String,
        specID: String,
        status: String,
        requirementResults: [RequirementResult],
        observedMetrics: [OpAmpEstimatedMetric],
        diagnostics: [OpAmpDesignDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.reportID = reportID
        self.specID = specID
        self.status = status
        self.requirementResults = requirementResults
        self.observedMetrics = observedMetrics
        self.diagnostics = diagnostics
    }
}
