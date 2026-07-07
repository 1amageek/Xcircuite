public struct XcircuiteSymbolicPlannerPDDLActionMapping: Codable, Sendable, Hashable {
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var pddlAction: String
    public var included: Bool
    public var preconditionAtoms: [String]
    public var effectAtoms: [String]
    public var actionCost: Double?
    public var actionCostUnit: String?
    public var actionCostSource: String?
    public var diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic]

    public init(
        actionID: String,
        domainID: String,
        operationID: String,
        pddlAction: String,
        included: Bool,
        preconditionAtoms: [String],
        effectAtoms: [String],
        actionCost: Double? = nil,
        actionCostUnit: String? = nil,
        actionCostSource: String? = nil,
        diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic] = []
    ) {
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.pddlAction = pddlAction
        self.included = included
        self.preconditionAtoms = preconditionAtoms
        self.effectAtoms = effectAtoms
        self.actionCost = actionCost
        self.actionCostUnit = actionCostUnit
        self.actionCostSource = actionCostSource
        self.diagnostics = diagnostics
    }
}
