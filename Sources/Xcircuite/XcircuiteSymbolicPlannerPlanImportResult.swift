import XcircuitePackage

public struct XcircuiteSymbolicPlannerPlanImportResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var importedActionCount: Int
    public var solverPlanArtifact: XcircuiteFileReference
    public var pddlExportArtifact: XcircuiteFileReference
    public var candidatePlanArtifact: XcircuiteFileReference
    public var candidatePlan: XcircuiteCandidatePlan
    public var diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        importedActionCount: Int,
        solverPlanArtifact: XcircuiteFileReference,
        pddlExportArtifact: XcircuiteFileReference,
        candidatePlanArtifact: XcircuiteFileReference,
        candidatePlan: XcircuiteCandidatePlan,
        diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.importedActionCount = importedActionCount
        self.solverPlanArtifact = solverPlanArtifact
        self.pddlExportArtifact = pddlExportArtifact
        self.candidatePlanArtifact = candidatePlanArtifact
        self.candidatePlan = candidatePlan
        self.diagnostics = diagnostics
    }
}
