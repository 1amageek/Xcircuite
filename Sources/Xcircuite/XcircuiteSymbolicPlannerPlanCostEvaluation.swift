public struct XcircuiteSymbolicPlannerPlanCostEvaluation: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var strategy: String
    public var planID: String
    public var planLength: Int
    public var evaluatedCost: Double
    public var evaluatedCostUnit: String
    public var stepCosts: [XcircuiteSymbolicPlannerPlanCostStep]

    public init(
        schemaVersion: Int = 1,
        strategy: String,
        planID: String,
        planLength: Int,
        evaluatedCost: Double,
        evaluatedCostUnit: String,
        stepCosts: [XcircuiteSymbolicPlannerPlanCostStep]
    ) {
        self.schemaVersion = schemaVersion
        self.strategy = strategy
        self.planID = planID
        self.planLength = planLength
        self.evaluatedCost = evaluatedCost
        self.evaluatedCostUnit = evaluatedCostUnit
        self.stepCosts = stepCosts
    }
}
