import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPDDLExportResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var domainName: String
    public var problemName: String
    public var problemPath: String
    public var problemTranslationAuditArtifact: ArtifactReference?
    public var actionDomainSnapshotArtifact: ArtifactReference
    public var domainArtifact: ArtifactReference
    public var problemArtifact: ArtifactReference
    public var exportArtifact: ArtifactReference
    public var export: XcircuiteSymbolicPlannerPDDLExport

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        domainName: String,
        problemName: String,
        problemPath: String,
        problemTranslationAuditArtifact: ArtifactReference? = nil,
        actionDomainSnapshotArtifact: ArtifactReference,
        domainArtifact: ArtifactReference,
        problemArtifact: ArtifactReference,
        exportArtifact: ArtifactReference,
        export: XcircuiteSymbolicPlannerPDDLExport
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.domainName = domainName
        self.problemName = problemName
        self.problemPath = problemPath
        self.problemTranslationAuditArtifact = problemTranslationAuditArtifact
        self.actionDomainSnapshotArtifact = actionDomainSnapshotArtifact
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.exportArtifact = exportArtifact
        self.export = export
    }
}
