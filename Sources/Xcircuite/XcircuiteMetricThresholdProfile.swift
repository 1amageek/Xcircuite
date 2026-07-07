import Foundation

public struct XcircuiteMetricThresholdProfile: Codable, Sendable, Hashable {
    public struct Threshold: Codable, Sendable, Hashable {
        public var metricID: String
        public var objectiveID: String?
        public var domain: String
        public var metricName: String
        public var direction: String
        public var targetValue: Double
        public var tolerance: Double?
        public var unit: String?
        public var severity: String
        public var sourceRefIDs: [String]

        public init(
            metricID: String,
            objectiveID: String? = nil,
            domain: String,
            metricName: String,
            direction: String,
            targetValue: Double,
            tolerance: Double? = nil,
            unit: String? = nil,
            severity: String,
            sourceRefIDs: [String] = []
        ) {
            self.metricID = metricID
            self.objectiveID = objectiveID
            self.domain = domain
            self.metricName = metricName
            self.direction = direction
            self.targetValue = targetValue
            self.tolerance = tolerance
            self.unit = unit
            self.severity = severity
            self.sourceRefIDs = sourceRefIDs
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var problemID: String?
    public var profileID: String
    public var generatedAt: String
    public var sourceRefs: [XcircuitePlanningReference]
    public var thresholds: [Threshold]
    public var policyNotes: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String? = nil,
        profileID: String,
        generatedAt: String,
        sourceRefs: [XcircuitePlanningReference] = [],
        thresholds: [Threshold],
        policyNotes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.profileID = profileID
        self.generatedAt = generatedAt
        self.sourceRefs = sourceRefs
        self.thresholds = thresholds
        self.policyNotes = policyNotes
    }
}
