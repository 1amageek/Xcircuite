import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPlanImportResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var importedActionCount: Int
    /// Artifact emitted by the external solver and persisted by the planning store.
    public var solverPlanArtifact: ArtifactReference
    /// PDDL export consumed while importing the solver plan.
    public var pddlExportArtifact: ArtifactReference
    /// Canonical candidate plan artifact generated from the solver output.
    public var candidatePlanArtifact: ArtifactReference
    public var candidatePlan: XcircuiteCandidatePlan
    public var diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        importedActionCount: Int,
        solverPlanArtifact: ArtifactReference,
        pddlExportArtifact: ArtifactReference,
        candidatePlanArtifact: ArtifactReference,
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
