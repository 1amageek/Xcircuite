import XcircuitePackage

public struct XcircuiteSymbolicPlannerPDDLExportResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var domainName: String
    public var problemName: String
    public var problemPath: String
    public var problemTranslationAuditArtifact: XcircuiteFileReference?
    public var actionDomainSnapshotArtifact: XcircuiteFileReference
    public var domainArtifact: XcircuiteFileReference
    public var problemArtifact: XcircuiteFileReference
    public var exportArtifact: XcircuiteFileReference
    public var export: XcircuiteSymbolicPlannerPDDLExport

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        domainName: String,
        problemName: String,
        problemPath: String,
        problemTranslationAuditArtifact: XcircuiteFileReference? = nil,
        actionDomainSnapshotArtifact: XcircuiteFileReference,
        domainArtifact: XcircuiteFileReference,
        problemArtifact: XcircuiteFileReference,
        exportArtifact: XcircuiteFileReference,
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
