public struct XcircuiteSymbolicPlannerInstalledSolverCandidateSpec: Codable, Sendable, Hashable {
    public var candidateID: String
    public var toolID: String
    public var displayName: String
    public var solverFamily: String
    public var executableNames: [String]
    public var executablePath: String?
    public var arguments: [String]
    public var timeoutSeconds: Double
    public var certificateFormat: String
    public var requireOptimality: Bool
    public var requireNativeCertificate: Bool

    public init(
        candidateID: String,
        toolID: String,
        displayName: String,
        solverFamily: String,
        executableNames: [String],
        executablePath: String? = nil,
        arguments: [String] = [],
        timeoutSeconds: Double = 300,
        certificateFormat: String,
        requireOptimality: Bool = false,
        requireNativeCertificate: Bool = true
    ) {
        self.candidateID = candidateID
        self.toolID = toolID
        self.displayName = displayName
        self.solverFamily = solverFamily
        self.executableNames = executableNames
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.certificateFormat = certificateFormat
        self.requireOptimality = requireOptimality
        self.requireNativeCertificate = requireNativeCertificate
    }
}
