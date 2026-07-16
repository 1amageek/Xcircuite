import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyComparison: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var comparisonID: String
    public var selectionPolicy: String
    public var requestedValidationArtifactIDs: [String]
    public var requestedValidationPaths: [String]
    public var selectedCandidateIndex: Int
    public var selectedToolID: String
    public var selectedValidationArtifact: ArtifactReference?
    public var candidateCount: Int
    public var passedCandidateCount: Int
    public var failedCandidateCount: Int
    public var candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult]
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        comparisonID: String,
        selectionPolicy: String,
        requestedValidationArtifactIDs: [String],
        requestedValidationPaths: [String],
        selectedCandidateIndex: Int,
        selectedToolID: String,
        selectedValidationArtifact: ArtifactReference?,
        candidateCount: Int,
        passedCandidateCount: Int,
        failedCandidateCount: Int,
        candidates: [XcircuiteSymbolicPlannerSolverFamilyCandidateResult],
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.comparisonID = comparisonID
        self.selectionPolicy = selectionPolicy
        self.requestedValidationArtifactIDs = requestedValidationArtifactIDs
        self.requestedValidationPaths = requestedValidationPaths
        self.selectedCandidateIndex = selectedCandidateIndex
        self.selectedToolID = selectedToolID
        self.selectedValidationArtifact = selectedValidationArtifact
        self.candidateCount = candidateCount
        self.passedCandidateCount = passedCandidateCount
        self.failedCandidateCount = failedCandidateCount
        self.candidates = candidates
        self.diagnostics = diagnostics
    }
}
