import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteImprovementPlanningArtifactGenerationResult: Codable, Sendable, Hashable {
    public var status: String
    public var runID: String
    public var problemID: String?
    public var numericRepairLoopPath: String
    public var accepted: Bool
    public var iterationCount: Int
    public var selectedCandidateID: String?
    public var thresholdProfileArtifact: ArtifactReference
    public var costCalibrationArtifact: ArtifactReference
    public var paretoCandidatesArtifact: ArtifactReference
    public var improvementLoopArtifact: ArtifactReference
    public var rejectedFeedbackLearningReportArtifact: ArtifactReference?
    public var diagnostics: [String]

    public init(
        status: String,
        runID: String,
        problemID: String?,
        numericRepairLoopPath: String,
        accepted: Bool,
        iterationCount: Int,
        selectedCandidateID: String? = nil,
        thresholdProfileArtifact: ArtifactReference,
        costCalibrationArtifact: ArtifactReference,
        paretoCandidatesArtifact: ArtifactReference,
        improvementLoopArtifact: ArtifactReference,
        rejectedFeedbackLearningReportArtifact: ArtifactReference? = nil,
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
