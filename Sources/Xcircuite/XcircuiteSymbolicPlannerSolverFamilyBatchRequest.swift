public struct XcircuiteSymbolicPlannerSolverFamilyBatchRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var comparisonID: String
    public var selectionPolicy: String
    public var candidates: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest]
    public var promoteSelectedPlan: Bool
    public var requireQualifiedPromotion: Bool
    public var verifyPromotedPlan: Bool

    public init(
        schemaVersion: Int = 1,
        runID: String,
        comparisonID: String = "solver-family-1",
        selectionPolicy: String = "prefer-qualified-health-replay-goals-proof-optimality-cost",
        candidates: [XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest],
        promoteSelectedPlan: Bool = true,
        requireQualifiedPromotion: Bool = true,
        verifyPromotedPlan: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.comparisonID = comparisonID
        self.selectionPolicy = selectionPolicy
        self.candidates = candidates
        self.promoteSelectedPlan = promoteSelectedPlan
        self.requireQualifiedPromotion = requireQualifiedPromotion
        self.verifyPromotedPlan = verifyPromotedPlan
    }
}
