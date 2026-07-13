import Foundation
import DesignFlowKernel

public struct XcircuiteImprovementPlanningArtifactGenerationResult: Codable, Sendable, Hashable {
    public var status: String
    public var runID: String
    public var problemID: String?
    public var numericRepairLoopPath: String
    public var accepted: Bool
    public var iterationCount: Int
    public var selectedCandidateID: String?
    public var thresholdProfileArtifact: XcircuiteFileReference
    public var costCalibrationArtifact: XcircuiteFileReference
    public var paretoCandidatesArtifact: XcircuiteFileReference
    public var improvementLoopArtifact: XcircuiteFileReference
    public var rejectedFeedbackLearningReportArtifact: XcircuiteFileReference?
    public var diagnostics: [String]

    public init(
        status: String,
        runID: String,
        problemID: String?,
        numericRepairLoopPath: String,
        accepted: Bool,
        iterationCount: Int,
        selectedCandidateID: String? = nil,
        thresholdProfileArtifact: XcircuiteFileReference,
        costCalibrationArtifact: XcircuiteFileReference,
        paretoCandidatesArtifact: XcircuiteFileReference,
        improvementLoopArtifact: XcircuiteFileReference,
        rejectedFeedbackLearningReportArtifact: XcircuiteFileReference? = nil,
        diagnostics: [String] = []
    ) {
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.numericRepairLoopPath = numericRepairLoopPath
        self.accepted = accepted
        self.iterationCount = iterationCount
        self.selectedCandidateID = selectedCandidateID
        self.thresholdProfileArtifact = thresholdProfileArtifact
        self.costCalibrationArtifact = costCalibrationArtifact
        self.paretoCandidatesArtifact = paretoCandidatesArtifact
        self.improvementLoopArtifact = improvementLoopArtifact
        self.rejectedFeedbackLearningReportArtifact = rejectedFeedbackLearningReportArtifact
        self.diagnostics = diagnostics
    }
}
