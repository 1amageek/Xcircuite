public struct XcircuiteSymbolicPlannerPlanReplayStepValidation: Codable, Sendable, Hashable {
    public var stepID: String
    public var order: Int
    public var actionID: String
    public var pddlAction: String?
    public var status: String
    public var preconditionAtoms: [String]
    public var missingPreconditionAtoms: [String]
    public var effectAtoms: [String]
    public var stateBefore: [String]
    public var stateAfter: [String]
    public var actionCost: Double

    public init(
        stepID: String,
        order: Int,
        actionID: String,
        pddlAction: String?,
        status: String,
        preconditionAtoms: [String],
        missingPreconditionAtoms: [String],
        effectAtoms: [String],
        stateBefore: [String],
        stateAfter: [String],
        actionCost: Double
    ) {
        self.stepID = stepID
        self.order = order
        self.actionID = actionID
        self.pddlAction = pddlAction
        self.status = status
        self.preconditionAtoms = preconditionAtoms
        self.missingPreconditionAtoms = missingPreconditionAtoms
        self.effectAtoms = effectAtoms
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.actionCost = actionCost
    }
}
