import XcircuitePackage

public struct XcircuiteSymbolicPlannerSolverCorpusCaseResult: Codable, Sendable, Hashable {
    public var caseID: String
    public var runID: String
    public var status: String
    public var expectedActionIDs: [String]
    public var observedActionIDs: [String]
    public var coverageTags: [String]
    public var goalCoverageStatus: String?
    public var missingGoalAtoms: [String]
    public var failureCodes: [String]
    public var qualificationArtifact: XcircuiteFileReference?
    public var planVerificationArtifact: XcircuiteFileReference?

    public init(
        caseID: String,
        runID: String,
        status: String,
        expectedActionIDs: [String],
        observedActionIDs: [String],
        coverageTags: [String],
        goalCoverageStatus: String?,
        missingGoalAtoms: [String],
        failureCodes: [String],
        qualificationArtifact: XcircuiteFileReference?,
        planVerificationArtifact: XcircuiteFileReference?
    ) {
        self.caseID = caseID
        self.runID = runID
        self.status = status
        self.expectedActionIDs = expectedActionIDs
        self.observedActionIDs = observedActionIDs
        self.coverageTags = coverageTags
        self.goalCoverageStatus = goalCoverageStatus
        self.missingGoalAtoms = missingGoalAtoms
        self.failureCodes = failureCodes
        self.qualificationArtifact = qualificationArtifact
        self.planVerificationArtifact = planVerificationArtifact
    }
}
