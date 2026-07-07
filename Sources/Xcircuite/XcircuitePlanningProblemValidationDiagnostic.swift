public struct XcircuitePlanningProblemValidationDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var refID: String?
    public var objectiveID: String?
    public var actionID: String?
    public var gateID: String?
    public var assumptionID: String?
    public var riskID: String?

    public init(
        severity: String,
        code: String,
        message: String,
        refID: String? = nil,
        objectiveID: String? = nil,
        actionID: String? = nil,
        gateID: String? = nil,
        assumptionID: String? = nil,
        riskID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.refID = refID
        self.objectiveID = objectiveID
        self.actionID = actionID
        self.gateID = gateID
        self.assumptionID = assumptionID
        self.riskID = riskID
    }
}
