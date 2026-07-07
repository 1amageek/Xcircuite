import ToolQualification

public struct XcircuiteSymbolicPlannerInstalledSolverCandidateResult: Codable, Sendable, Hashable {
    public var candidateID: String
    public var toolID: String
    public var displayName: String
    public var solverFamily: String
    public var status: String
    public var executablePath: String?
    public var executableNames: [String]
    public var searchedPaths: [String]
    public var certificateFormat: String
    public var requireOptimality: Bool
    public var requireNativeCertificate: Bool
    public var descriptor: ToolDescriptor?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        candidateID: String,
        toolID: String,
        displayName: String,
        solverFamily: String,
        status: String,
        executablePath: String? = nil,
        executableNames: [String],
        searchedPaths: [String],
        certificateFormat: String,
        requireOptimality: Bool,
        requireNativeCertificate: Bool,
        descriptor: ToolDescriptor? = nil,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.candidateID = candidateID
        self.toolID = toolID
        self.displayName = displayName
        self.solverFamily = solverFamily
        self.status = status
        self.executablePath = executablePath
        self.executableNames = executableNames
        self.searchedPaths = searchedPaths
        self.certificateFormat = certificateFormat
        self.requireOptimality = requireOptimality
        self.requireNativeCertificate = requireNativeCertificate
        self.descriptor = descriptor
        self.diagnostics = diagnostics
    }
}
