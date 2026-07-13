import Foundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanRiskApprovalResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var approvalID: String
    public var approvalPath: String
    public var approval: XcircuiteApprovalRecord
    public var approvalArtifact: XcircuiteFileReference
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        approvalID: String,
        approvalPath: String,
        approval: XcircuiteApprovalRecord,
        approvalArtifact: XcircuiteFileReference,
        nextActions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.approvalID = approvalID
        self.approvalPath = approvalPath
        self.approval = approval
        self.approvalArtifact = approvalArtifact
        self.nextActions = nextActions
    }
}
