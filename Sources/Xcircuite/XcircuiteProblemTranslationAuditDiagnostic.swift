public struct XcircuiteProblemTranslationAuditDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var sourceRefID: String?
    public var intentClauseID: String?
    public var objectiveID: String?
    public var constraintID: String?
    public var actionID: String?
    public var gateID: String?
    public var goalAtom: String?
    public var nextActions: [String]

    public init(
        severity: String,
        code: String,
        message: String,
        sourceRefID: String? = nil,
        intentClauseID: String? = nil,
        objectiveID: String? = nil,
        constraintID: String? = nil,
        actionID: String? = nil,
        gateID: String? = nil,
        goalAtom: String? = nil,
        nextActions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.sourceRefID = sourceRefID
        self.intentClauseID = intentClauseID
        self.objectiveID = objectiveID
        self.constraintID = constraintID
        self.actionID = actionID
        self.gateID = gateID
        self.goalAtom = goalAtom
        self.nextActions = nextActions
    }
}
