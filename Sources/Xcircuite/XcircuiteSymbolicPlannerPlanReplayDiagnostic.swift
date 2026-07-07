public struct XcircuiteSymbolicPlannerPlanReplayDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var stepID: String?
    public var actionID: String?
    public var pddlAction: String?
    public var atoms: [String]

    public init(
        severity: String,
        code: String,
        message: String,
        stepID: String? = nil,
        actionID: String? = nil,
        pddlAction: String? = nil,
        atoms: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.stepID = stepID
        self.actionID = actionID
        self.pddlAction = pddlAction
        self.atoms = atoms
    }
}
