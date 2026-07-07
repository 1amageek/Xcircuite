public struct XcircuiteSymbolicPlannerPlanCostStep: Codable, Sendable, Hashable {
    public var stepID: String
    public var actionID: String
    public var order: Int
    public var cost: Double

    public init(
        stepID: String,
        actionID: String,
        order: Int,
        cost: Double
    ) {
        self.stepID = stepID
        self.actionID = actionID
        self.order = order
        self.cost = cost
    }
}
