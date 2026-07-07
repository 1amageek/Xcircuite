import XcircuitePackage

public struct XcircuiteProblemTranslationAuditResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var problemPath: String
    public var audit: XcircuiteProblemTranslationAudit
    public var auditArtifact: XcircuiteFileReference

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        problemPath: String,
        audit: XcircuiteProblemTranslationAudit,
        auditArtifact: XcircuiteFileReference
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.problemPath = problemPath
        self.audit = audit
        self.auditArtifact = auditArtifact
    }
}
