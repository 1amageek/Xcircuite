public struct XcircuiteSymbolicPlannerInstalledSolverLaneRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var laneID: String
    public var selectionPolicy: String
    public var searchPaths: [String]
    public var candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateSpec]
    public var promoteSelectedPlan: Bool
    public var requireQualifiedPromotion: Bool
    public var verifyPromotedPlan: Bool

    public init(
        schemaVersion: Int = 1,
        runID: String,
        laneID: String = "installed-symbolic-planner-solvers",
        selectionPolicy: String = "prefer-qualified-health-replay-goals-proof-optimality-cost",
        searchPaths: [String] = [],
        candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateSpec] = [],
        promoteSelectedPlan: Bool = false,
        requireQualifiedPromotion: Bool = true,
        verifyPromotedPlan: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.laneID = laneID
        self.selectionPolicy = selectionPolicy
        self.searchPaths = searchPaths
        self.candidates = candidates
        self.promoteSelectedPlan = promoteSelectedPlan
        self.requireQualifiedPromotion = requireQualifiedPromotion
        self.verifyPromotedPlan = verifyPromotedPlan
    }
}
