import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyBatchRun: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var comparisonID: String
    public var selectionPolicy: String
    public var candidateCount: Int
    public var qualifiedCandidateCount: Int
    public var failedCandidateCount: Int
    public var candidates: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateResult]
    public var comparisonArtifact: XcircuiteFileReference
    public var promotionArtifact: XcircuiteFileReference?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        comparisonID: String,
        selectionPolicy: String,
        candidateCount: Int,
        qualifiedCandidateCount: Int,
        failedCandidateCount: Int,
        candidates: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateResult],
        comparisonArtifact: XcircuiteFileReference,
        promotionArtifact: XcircuiteFileReference?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.comparisonID = comparisonID
        self.selectionPolicy = selectionPolicy
        self.candidateCount = candidateCount
        self.qualifiedCandidateCount = qualifiedCandidateCount
        self.failedCandidateCount = failedCandidateCount
        self.candidates = candidates
        self.comparisonArtifact = comparisonArtifact
        self.promotionArtifact = promotionArtifact
        self.diagnostics = diagnostics
    }
}
