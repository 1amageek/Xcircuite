public struct XcircuiteSymbolicPlannerPlanImportDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var pddlAction: String?

    public init(
        severity: String,
        code: String,
        message: String,
        pddlAction: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.pddlAction = pddlAction
    }
}
