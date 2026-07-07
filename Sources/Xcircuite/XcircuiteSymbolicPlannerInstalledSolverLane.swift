public struct XcircuiteSymbolicPlannerInstalledSolverLane: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var laneID: String
    public var selectionPolicy: String
    public var searchedPaths: [String]
    public var candidateCount: Int
    public var availableCandidateCount: Int
    public var unavailableCandidateCount: Int
    public var candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateResult]
    public var batchRequest: XcircuiteSymbolicPlannerSolverFamilyBatchRequest?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        laneID: String,
        selectionPolicy: String,
        searchedPaths: [String],
        candidateCount: Int,
        availableCandidateCount: Int,
        unavailableCandidateCount: Int,
        candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateResult],
        batchRequest: XcircuiteSymbolicPlannerSolverFamilyBatchRequest? = nil,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.laneID = laneID
        self.selectionPolicy = selectionPolicy
        self.searchedPaths = searchedPaths
        self.candidateCount = candidateCount
        self.availableCandidateCount = availableCandidateCount
        self.unavailableCandidateCount = unavailableCandidateCount
        self.candidates = candidates
        self.batchRequest = batchRequest
        self.diagnostics = diagnostics
    }
}
