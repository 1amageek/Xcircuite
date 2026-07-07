import XcircuitePackage

public struct XcircuiteSymbolicPlannerProofValidation: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var toolID: String
    public var proofArtifact: XcircuiteFileReference
    public var domainArtifact: XcircuiteFileReference?
    public var problemArtifact: XcircuiteFileReference?
    public var pddlExportArtifact: XcircuiteFileReference?
    public var solverPlanArtifact: XcircuiteFileReference?
    public var proofCheckerExecutablePath: String
    public var proofCheckerArguments: [String]
    public var proofCheckerTimeoutSeconds: Double
    public var workingDirectoryPath: String
    public var standardOutputArtifact: XcircuiteFileReference?
    public var standardErrorArtifact: XcircuiteFileReference?
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
        proofArtifact: XcircuiteFileReference,
        domainArtifact: XcircuiteFileReference? = nil,
        problemArtifact: XcircuiteFileReference? = nil,
        pddlExportArtifact: XcircuiteFileReference? = nil,
        solverPlanArtifact: XcircuiteFileReference? = nil,
        proofCheckerExecutablePath: String,
        proofCheckerArguments: [String],
        proofCheckerTimeoutSeconds: Double,
        workingDirectoryPath: String,
        standardOutputArtifact: XcircuiteFileReference? = nil,
        standardErrorArtifact: XcircuiteFileReference? = nil,
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
