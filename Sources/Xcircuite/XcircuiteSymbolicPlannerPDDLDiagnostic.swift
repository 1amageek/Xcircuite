public struct XcircuiteSymbolicPlannerPDDLDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var actionID: String?
    public var objectiveID: String?

    public init(
        severity: String,
        code: String,
        message: String,
        actionID: String? = nil,
        objectiveID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.actionID = actionID
        self.objectiveID = objectiveID
    }
}
