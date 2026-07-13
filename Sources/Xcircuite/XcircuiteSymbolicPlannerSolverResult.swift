import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var exitCode: Int32?
    public var didTimeout: Bool
    public var didCancel: Bool
    public var domainArtifact: XcircuiteFileReference
    public var problemArtifact: XcircuiteFileReference
    public var pddlExportArtifact: XcircuiteFileReference?
    public var runArtifact: XcircuiteFileReference
    public var standardOutputArtifact: XcircuiteFileReference
    public var standardErrorArtifact: XcircuiteFileReference
    public var solverPlanArtifact: XcircuiteFileReference?
    public var planReplayValidationArtifact: XcircuiteFileReference?
    public var solverMetadata: XcircuiteSymbolicPlannerSolverMetadata?
    public var importResult: XcircuiteSymbolicPlannerPlanImportResult?
    public var planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        exitCode: Int32?,
        didTimeout: Bool,
        didCancel: Bool,
        domainArtifact: XcircuiteFileReference,
        problemArtifact: XcircuiteFileReference,
        pddlExportArtifact: XcircuiteFileReference?,
        runArtifact: XcircuiteFileReference,
        standardOutputArtifact: XcircuiteFileReference,
        standardErrorArtifact: XcircuiteFileReference,
        solverPlanArtifact: XcircuiteFileReference?,
        planReplayValidationArtifact: XcircuiteFileReference? = nil,
        solverMetadata: XcircuiteSymbolicPlannerSolverMetadata? = nil,
        importResult: XcircuiteSymbolicPlannerPlanImportResult?,
        planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation? = nil,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.exitCode = exitCode
        self.didTimeout = didTimeout
        self.didCancel = didCancel
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.pddlExportArtifact = pddlExportArtifact
        self.runArtifact = runArtifact
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
        self.solverPlanArtifact = solverPlanArtifact
        self.planReplayValidationArtifact = planReplayValidationArtifact
        self.solverMetadata = solverMetadata
        self.importResult = importResult
        self.planReplayValidation = planReplayValidation
        self.diagnostics = diagnostics
    }
}
