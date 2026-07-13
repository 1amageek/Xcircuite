import CircuiteFoundation
import DesignFlowKernel

public struct XcircuitePlanningProblemValidationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var problemPath: String
    public var validation: XcircuitePlanningProblemValidation
    public var validationArtifact: ArtifactReference
    public var problemTranslationAuditArtifact: ArtifactReference?
    public var actionDomainSnapshotArtifact: ArtifactReference?

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        problemPath: String,
        validation: XcircuitePlanningProblemValidation,
        validationArtifact: ArtifactReference,
        problemTranslationAuditArtifact: ArtifactReference? = nil,
        actionDomainSnapshotArtifact: ArtifactReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.problemPath = problemPath
        self.validation = validation
        self.validationArtifact = validationArtifact
        self.problemTranslationAuditArtifact = problemTranslationAuditArtifact
        self.actionDomainSnapshotArtifact = actionDomainSnapshotArtifact
    }
}
