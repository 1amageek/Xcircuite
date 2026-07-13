import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanGenerationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var executionReadiness: String
    public var problemPath: String
    public var candidatePlanArtifact: ArtifactReference
    public var problemTranslationAuditArtifact: ArtifactReference?
    public var actionDomainSnapshotArtifact: ArtifactReference?
    public var symbolicPlannerTrace: XcircuiteSymbolicPlannerTrace?
    public var symbolicPlannerTraceArtifact: ArtifactReference?

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        executionReadiness: String,
        problemPath: String,
        candidatePlanArtifact: ArtifactReference,
        problemTranslationAuditArtifact: ArtifactReference? = nil,
        actionDomainSnapshotArtifact: ArtifactReference? = nil,
        symbolicPlannerTrace: XcircuiteSymbolicPlannerTrace? = nil,
        symbolicPlannerTraceArtifact: ArtifactReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.executionReadiness = executionReadiness
        self.problemPath = problemPath
        self.candidatePlanArtifact = candidatePlanArtifact
        self.problemTranslationAuditArtifact = problemTranslationAuditArtifact
        self.actionDomainSnapshotArtifact = actionDomainSnapshotArtifact
        self.symbolicPlannerTrace = symbolicPlannerTrace
        self.symbolicPlannerTraceArtifact = symbolicPlannerTraceArtifact
    }
}
