import Foundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanGenerationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var executionReadiness: String
    public var problemPath: String
    public var candidatePlanArtifact: XcircuiteFileReference
    public var problemTranslationAuditArtifact: XcircuiteFileReference?
    public var actionDomainSnapshotArtifact: XcircuiteFileReference?
    public var symbolicPlannerTrace: XcircuiteSymbolicPlannerTrace?
    public var symbolicPlannerTraceArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        executionReadiness: String,
        problemPath: String,
        candidatePlanArtifact: XcircuiteFileReference,
        problemTranslationAuditArtifact: XcircuiteFileReference? = nil,
        actionDomainSnapshotArtifact: XcircuiteFileReference? = nil,
        symbolicPlannerTrace: XcircuiteSymbolicPlannerTrace? = nil,
        symbolicPlannerTraceArtifact: XcircuiteFileReference? = nil
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
