import Foundation
import DesignFlowKernel

public struct XcircuiteParameterCandidatePlanSynthesisResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var selectedCandidateID: String
    public var selectedCandidateRank: Int
    public var planID: String
    public var executionReadiness: String
    public var problemPath: String
    public var parameterCandidatesPath: String
    public var rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary?
    public var skippedRejectedCandidateIDs: [String]?
    public var selectionTrace: XcircuiteParameterCandidateSelectionTrace?
    public var selectionTraceArtifact: XcircuiteFileReference?
    public var candidatePlanArtifact: XcircuiteFileReference

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        selectedCandidateID: String,
        selectedCandidateRank: Int,
        planID: String,
        executionReadiness: String,
        problemPath: String,
        parameterCandidatesPath: String,
        rejectedPlanFeedback: XcircuiteRejectedPlanFeedbackSummary? = nil,
        skippedRejectedCandidateIDs: [String]? = nil,
        selectionTrace: XcircuiteParameterCandidateSelectionTrace? = nil,
        selectionTraceArtifact: XcircuiteFileReference? = nil,
        candidatePlanArtifact: XcircuiteFileReference
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.selectedCandidateID = selectedCandidateID
        self.selectedCandidateRank = selectedCandidateRank
        self.planID = planID
        self.executionReadiness = executionReadiness
        self.problemPath = problemPath
        self.parameterCandidatesPath = parameterCandidatesPath
        self.rejectedPlanFeedback = rejectedPlanFeedback
        self.skippedRejectedCandidateIDs = skippedRejectedCandidateIDs
        self.selectionTrace = selectionTrace
        self.selectionTraceArtifact = selectionTraceArtifact
        self.candidatePlanArtifact = candidatePlanArtifact
    }
}
