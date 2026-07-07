import Foundation

public struct XcircuiteCandidatePlanGenerationRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var rejectedPlansArtifactID: String?
    public var rejectedPlansPath: String?
    public var metricThresholdProfileArtifactID: String?
    public var metricThresholdProfilePath: String?
    public var costCalibrationArtifactID: String?
    public var costCalibrationPath: String?
    public var paretoCandidatesArtifactID: String?
    public var paretoCandidatesPath: String?
    public var strategy: String
    public var calibrationPolicy: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        rejectedPlansArtifactID: String? = nil,
        rejectedPlansPath: String? = nil,
        metricThresholdProfileArtifactID: String? = nil,
        metricThresholdProfilePath: String? = nil,
        costCalibrationArtifactID: String? = nil,
        costCalibrationPath: String? = nil,
        paretoCandidatesArtifactID: String? = nil,
        paretoCandidatesPath: String? = nil,
        strategy: String = "first-ready-action-per-objective",
        calibrationPolicy: String? = "disabled"
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.rejectedPlansArtifactID = rejectedPlansArtifactID
        self.rejectedPlansPath = rejectedPlansPath
        self.metricThresholdProfileArtifactID = metricThresholdProfileArtifactID
        self.metricThresholdProfilePath = metricThresholdProfilePath
        self.costCalibrationArtifactID = costCalibrationArtifactID
        self.costCalibrationPath = costCalibrationPath
        self.paretoCandidatesArtifactID = paretoCandidatesArtifactID
        self.paretoCandidatesPath = paretoCandidatesPath
        self.strategy = strategy
        self.calibrationPolicy = calibrationPolicy
    }
}
