public struct XcircuiteSymbolicPlannerSolverDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String

    public init(
        severity: String,
        code: String,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}
