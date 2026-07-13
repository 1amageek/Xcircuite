import Foundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerFamilyCandidateResult: Codable, Sendable, Hashable {
    public var candidateIndex: Int
    public var requestedStrategy: String
    public var effectiveStrategy: String
    public var status: String
    public var selected: Bool
    public var selectionScore: Int
    public var scoreComponents: [XcircuiteSymbolicPlannerFamilySelectionScoreComponent]
    public var planID: String
    public var executionReadiness: String
    public var goalCoverageStatus: String
    public var selectedActionIDs: [String]
    public var unresolvedObjectiveIDs: [String]
    public var missingGoalAtoms: [String]
    public var blockers: [String]
    public var candidatePlanArtifact: XcircuiteFileReference
    public var symbolicPlannerTraceArtifact: XcircuiteFileReference
    public var policyTrace: XcircuiteSymbolicPlannerPolicyTrace?
    public var calibrationTrace: XcircuiteSymbolicPlannerCalibrationTrace?

    public init(
        candidateIndex: Int,
        requestedStrategy: String,
        effectiveStrategy: String,
        status: String,
        selected: Bool,
        selectionScore: Int,
        scoreComponents: [XcircuiteSymbolicPlannerFamilySelectionScoreComponent],
        planID: String,
        executionReadiness: String,
        goalCoverageStatus: String,
        selectedActionIDs: [String],
        unresolvedObjectiveIDs: [String],
        missingGoalAtoms: [String],
        blockers: [String],
        candidatePlanArtifact: XcircuiteFileReference,
        symbolicPlannerTraceArtifact: XcircuiteFileReference,
        policyTrace: XcircuiteSymbolicPlannerPolicyTrace? = nil,
        calibrationTrace: XcircuiteSymbolicPlannerCalibrationTrace? = nil
    ) {
        self.candidateIndex = candidateIndex
        self.requestedStrategy = requestedStrategy
        self.effectiveStrategy = effectiveStrategy
        self.status = status
        self.selected = selected
        self.selectionScore = selectionScore
        self.scoreComponents = scoreComponents
        self.planID = planID
        self.executionReadiness = executionReadiness
        self.goalCoverageStatus = goalCoverageStatus
        self.selectedActionIDs = selectedActionIDs
        self.unresolvedObjectiveIDs = unresolvedObjectiveIDs
        self.missingGoalAtoms = missingGoalAtoms
        self.blockers = blockers
        self.candidatePlanArtifact = candidatePlanArtifact
        self.symbolicPlannerTraceArtifact = symbolicPlannerTraceArtifact
        self.policyTrace = policyTrace
        self.calibrationTrace = calibrationTrace
    }
}
