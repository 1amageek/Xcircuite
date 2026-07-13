import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyComparison: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var comparisonID: String
    public var selectionPolicy: String
    public var requestedQualificationArtifactIDs: [String]
    public var requestedQualificationPaths: [String]
    public var selectedCandidateIndex: Int
    public var selectedToolID: String
    public var selectedQualificationArtifact: ArtifactReference?
    public var candidateCount: Int
    public var qualifiedCandidateCount: Int
    public var failedCandidateCount: Int
    public var candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult]
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        comparisonID: String,
        selectionPolicy: String,
        requestedQualificationArtifactIDs: [String],
        requestedQualificationPaths: [String],
        selectedCandidateIndex: Int,
        selectedToolID: String,
        selectedQualificationArtifact: ArtifactReference?,
        candidateCount: Int,
        qualifiedCandidateCount: Int,
        failedCandidateCount: Int,
        candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult],
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.comparisonID = comparisonID
        self.selectionPolicy = selectionPolicy
        self.requestedQualificationArtifactIDs = requestedQualificationArtifactIDs
        self.requestedQualificationPaths = requestedQualificationPaths
        self.selectedCandidateIndex = selectedCandidateIndex
        self.selectedToolID = selectedToolID
        self.selectedQualificationArtifact = selectedQualificationArtifact
        self.candidateCount = candidateCount
        self.qualifiedCandidateCount = qualifiedCandidateCount
        self.failedCandidateCount = failedCandidateCount
        self.candidates = candidates
        self.diagnostics = diagnostics
    }
}
