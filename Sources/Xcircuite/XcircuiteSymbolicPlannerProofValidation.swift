import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerProofValidation: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var toolID: String
    public var proofArtifact: ArtifactReference
    public var domainArtifact: ArtifactReference?
    public var problemArtifact: ArtifactReference?
    public var pddlExportArtifact: ArtifactReference?
    public var solverPlanArtifact: ArtifactReference?
    public var proofCheckerExecutablePath: String
    public var proofCheckerArguments: [String]
    public var proofCheckerTimeoutSeconds: Double
    public var workingDirectoryPath: String
    public var standardOutputArtifact: ArtifactReference?
    public var standardErrorArtifact: ArtifactReference?
    public var exitCode: Int32?
    public var didTimeout: Bool
    public var didCancel: Bool
    public var startedAt: String
    public var finishedAt: String
    public var diagnostics: [XcircuiteSymbolicPlannerProofValidationDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        toolID: String,
        proofArtifact: ArtifactReference,
        domainArtifact: ArtifactReference? = nil,
        problemArtifact: ArtifactReference? = nil,
        pddlExportArtifact: ArtifactReference? = nil,
        solverPlanArtifact: ArtifactReference? = nil,
        proofCheckerExecutablePath: String,
        proofCheckerArguments: [String],
        proofCheckerTimeoutSeconds: Double,
        workingDirectoryPath: String,
        standardOutputArtifact: ArtifactReference? = nil,
        standardErrorArtifact: ArtifactReference? = nil,
        exitCode: Int32?,
        didTimeout: Bool,
        didCancel: Bool,
        startedAt: String,
        finishedAt: String,
        diagnostics: [XcircuiteSymbolicPlannerProofValidationDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.toolID = toolID
        self.proofArtifact = proofArtifact
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.pddlExportArtifact = pddlExportArtifact
        self.solverPlanArtifact = solverPlanArtifact
        self.proofCheckerExecutablePath = proofCheckerExecutablePath
        self.proofCheckerArguments = proofCheckerArguments
        self.proofCheckerTimeoutSeconds = proofCheckerTimeoutSeconds
        self.workingDirectoryPath = workingDirectoryPath
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
        self.exitCode = exitCode
        self.didTimeout = didTimeout
        self.didCancel = didCancel
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.diagnostics = diagnostics
    }
}
