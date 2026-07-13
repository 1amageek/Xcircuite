import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverCertificateParseResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var toolID: String
    public var requestedFormat: String
    public var detectedFormat: String?
    public var sourceArtifact: XcircuiteFileReference
    public var certificate: XcircuiteSymbolicPlannerSolverCertificate?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        toolID: String,
        requestedFormat: String,
        detectedFormat: String? = nil,
        sourceArtifact: XcircuiteFileReference,
        certificate: XcircuiteSymbolicPlannerSolverCertificate? = nil,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.toolID = toolID
        self.requestedFormat = requestedFormat
        self.detectedFormat = detectedFormat
        self.sourceArtifact = sourceArtifact
        self.certificate = certificate
        self.diagnostics = diagnostics
    }
}
