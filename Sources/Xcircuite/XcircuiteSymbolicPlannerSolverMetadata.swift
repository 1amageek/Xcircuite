public struct XcircuiteSymbolicPlannerSolverMetadata: Codable, Sendable, Hashable {
    public var planCost: Double?
    public var planCostUnit: String?
    public var planLength: Int?
    public var makespan: Double?
    public var optimalityStatus: String?
    public var evidenceLines: [String]

    public init(
        planCost: Double? = nil,
        planCostUnit: String? = nil,
        planLength: Int? = nil,
        makespan: Double? = nil,
        optimalityStatus: String? = nil,
        evidenceLines: [String] = []
    ) {
        self.planCost = planCost
        self.planCostUnit = planCostUnit
        self.planLength = planLength
        self.makespan = makespan
        self.optimalityStatus = optimalityStatus
        self.evidenceLines = evidenceLines
    }
}
