import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverExecutionReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var executablePath: String
    public var arguments: [String]
    public var timeoutSeconds: Double
    public var workingDirectoryPath: String
    public var domainArtifact: XcircuiteFileReference
    public var problemArtifact: XcircuiteFileReference
    public var pddlExportArtifact: XcircuiteFileReference?
    public var planReplayValidationArtifact: XcircuiteFileReference?
    public var planReplayValidationStatus: String?
    public var solverPlanOutputPath: String?
    public var solverPlanSource: String?
    public var solverMetadata: XcircuiteSymbolicPlannerSolverMetadata?
    public var exitCode: Int32?
    public var didTimeout: Bool
    public var didCancel: Bool
    public var startedAt: String
    public var finishedAt: String
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        executablePath: String,
        arguments: [String],
        timeoutSeconds: Double,
        workingDirectoryPath: String,
        domainArtifact: XcircuiteFileReference,
        problemArtifact: XcircuiteFileReference,
        pddlExportArtifact: XcircuiteFileReference?,
        planReplayValidationArtifact: XcircuiteFileReference? = nil,
        planReplayValidationStatus: String? = nil,
        solverPlanOutputPath: String?,
        solverPlanSource: String?,
        solverMetadata: XcircuiteSymbolicPlannerSolverMetadata? = nil,
        exitCode: Int32?,
        didTimeout: Bool,
        didCancel: Bool,
        startedAt: String,
        finishedAt: String,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectoryPath = workingDirectoryPath
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.pddlExportArtifact = pddlExportArtifact
        self.planReplayValidationArtifact = planReplayValidationArtifact
        self.planReplayValidationStatus = planReplayValidationStatus
        self.solverPlanOutputPath = solverPlanOutputPath
        self.solverPlanSource = solverPlanSource
        self.solverMetadata = solverMetadata
        self.exitCode = exitCode
        self.didTimeout = didTimeout
        self.didCancel = didCancel
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.diagnostics = diagnostics
    }
}
