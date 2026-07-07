public struct XcircuiteSymbolicPlannerSolverCertificateParseResultPayload: Sendable, Hashable {
    public var status: String
    public var detectedFormat: String?
    public var certificate: XcircuiteSymbolicPlannerSolverCertificate?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        status: String,
        detectedFormat: String?,
        certificate: XcircuiteSymbolicPlannerSolverCertificate?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        self.status = status
        self.detectedFormat = detectedFormat
        self.certificate = certificate
        self.diagnostics = diagnostics
    }
}
