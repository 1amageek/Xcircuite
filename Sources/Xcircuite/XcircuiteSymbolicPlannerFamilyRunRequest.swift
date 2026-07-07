import Foundation

public struct XcircuiteSymbolicPlannerFamilyRunRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var familyRunID: String
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
    public var strategies: [String]
    public var calibrationPolicy: String?
    public var selectionPolicy: String

    public init(
        runID: String,
        familyRunID: String = "family-run-1",
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
        strategies: [String] = [
            "first-ready-action-per-objective",
            "state-aware-objective-ordering",
        ],
        calibrationPolicy: String? = "disabled",
        selectionPolicy: String = "prefer-ready-then-goal-coverage-then-score"
    ) {
        self.runID = runID
        self.familyRunID = familyRunID
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
        self.strategies = strategies
        self.calibrationPolicy = calibrationPolicy
        self.selectionPolicy = selectionPolicy
    }
}
