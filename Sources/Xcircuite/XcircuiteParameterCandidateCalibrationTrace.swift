import Foundation

public struct XcircuiteParameterCandidateCalibrationTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var strategy: String
    public var metricThresholdProfilePath: String?
    public var costCalibrationPath: String?
    public var paretoCandidatesPath: String?
    public var thresholdCount: Int
    public var calibratedTermCount: Int
    public var observationCount: Int
    public var paretoCandidateCount: Int
    public var appliedCandidateCount: Int
    public var matchedSourceCandidateIDs: [String]
    public var matchedGateIDs: [String]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        strategy: String,
        metricThresholdProfilePath: String? = nil,
        costCalibrationPath: String? = nil,
        paretoCandidatesPath: String? = nil,
        thresholdCount: Int,
        calibratedTermCount: Int,
        observationCount: Int,
        paretoCandidateCount: Int,
        appliedCandidateCount: Int,
        matchedSourceCandidateIDs: [String] = [],
        matchedGateIDs: [String] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.strategy = strategy
        self.metricThresholdProfilePath = metricThresholdProfilePath
        self.costCalibrationPath = costCalibrationPath
        self.paretoCandidatesPath = paretoCandidatesPath
        self.thresholdCount = thresholdCount
        self.calibratedTermCount = calibratedTermCount
        self.observationCount = observationCount
        self.paretoCandidateCount = paretoCandidateCount
        self.appliedCandidateCount = appliedCandidateCount
        self.matchedSourceCandidateIDs = matchedSourceCandidateIDs
        self.matchedGateIDs = matchedGateIDs
        self.diagnostics = diagnostics
    }
}
