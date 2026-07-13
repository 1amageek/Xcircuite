import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyCandidateResult: Codable, Sendable, Hashable {
    public var candidateIndex: Int
    public var status: String
    public var selected: Bool
    public var selectionScore: Int
    public var scoreComponents: [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent]
    public var toolID: String
    public var qualificationStatus: String
    public var toolHealthStatus: String
    public var solverRunStatus: String
    public var expectedActionIDs: [String]
    public var observedActionIDs: [String]
    public var missingExpectedActionIDs: [String]
    public var goalCoverageStatus: String?
    public var missingGoalAtoms: [String]
    public var planReplayStatus: String?
    public var proofValidationStatus: String?
    public var optimalityStatus: String?
    public var evaluatedCost: Double?
    public var maximumSolverCost: Double?
    public var solverPlanLength: Int?
    public var solverExitCode: Int32?
    public var didTimeout: Bool
    public var didCancel: Bool
    public var qualificationArtifact: XcircuiteFileReference?
    public var nativeCertificateArtifact: XcircuiteFileReference?
    public var planVerificationArtifact: XcircuiteFileReference?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        candidateIndex: Int,
        status: String,
        selected: Bool,
        selectionScore: Int,
        scoreComponents: [XcircuiteSymbolicPlannerSolverFamilySelectionScoreComponent],
        toolID: String,
        qualificationStatus: String,
        toolHealthStatus: String,
        solverRunStatus: String,
        expectedActionIDs: [String],
        observedActionIDs: [String],
        missingExpectedActionIDs: [String],
        goalCoverageStatus: String?,
        missingGoalAtoms: [String],
        planReplayStatus: String?,
        proofValidationStatus: String?,
        optimalityStatus: String?,
        evaluatedCost: Double?,
        maximumSolverCost: Double?,
        solverPlanLength: Int?,
        solverExitCode: Int32?,
        didTimeout: Bool,
        didCancel: Bool,
        qualificationArtifact: XcircuiteFileReference?,
        nativeCertificateArtifact: XcircuiteFileReference? = nil,
        planVerificationArtifact: XcircuiteFileReference?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        self.candidateIndex = candidateIndex
        self.status = status
        self.selected = selected
        self.selectionScore = selectionScore
        self.scoreComponents = scoreComponents
        self.toolID = toolID
        self.qualificationStatus = qualificationStatus
        self.toolHealthStatus = toolHealthStatus
        self.solverRunStatus = solverRunStatus
        self.expectedActionIDs = expectedActionIDs
        self.observedActionIDs = observedActionIDs
        self.missingExpectedActionIDs = missingExpectedActionIDs
        self.goalCoverageStatus = goalCoverageStatus
        self.missingGoalAtoms = missingGoalAtoms
        self.planReplayStatus = planReplayStatus
        self.proofValidationStatus = proofValidationStatus
        self.optimalityStatus = optimalityStatus
        self.evaluatedCost = evaluatedCost
        self.maximumSolverCost = maximumSolverCost
        self.solverPlanLength = solverPlanLength
        self.solverExitCode = solverExitCode
        self.didTimeout = didTimeout
        self.didCancel = didCancel
        self.qualificationArtifact = qualificationArtifact
        self.nativeCertificateArtifact = nativeCertificateArtifact
        self.planVerificationArtifact = planVerificationArtifact
        self.diagnostics = diagnostics
    }
}
