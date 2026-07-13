import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var exitCode: Int32?
    public var didTimeout: Bool
    public var didCancel: Bool
    public var domainArtifact: ArtifactReference
    public var problemArtifact: ArtifactReference
    public var pddlExportArtifact: ArtifactReference?
    public var runArtifact: ArtifactReference
    public var standardOutputArtifact: ArtifactReference
    public var standardErrorArtifact: ArtifactReference
    public var solverPlanArtifact: ArtifactReference?
    public var planReplayValidationArtifact: ArtifactReference?
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
        domainArtifact: ArtifactReference,
        problemArtifact: ArtifactReference,
        pddlExportArtifact: ArtifactReference?,
        runArtifact: ArtifactReference,
        standardOutputArtifact: ArtifactReference,
        standardErrorArtifact: ArtifactReference,
        solverPlanArtifact: ArtifactReference?,
        planReplayValidationArtifact: ArtifactReference? = nil,
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
