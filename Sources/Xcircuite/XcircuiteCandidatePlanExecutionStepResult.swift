import Foundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanExecutionStepResult: Codable, Sendable, Hashable {
    public var stepID: String
    public var order: Int
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var status: String
    public var artifactRefs: [XcircuiteFileReference]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var nextActions: [String]

    public init(
        stepID: String,
        order: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        status: String,
        artifactRefs: [XcircuiteFileReference] = [],
        diagnostics: [XcircuitePlanVerificationDiagnostic] = [],
        nextActions: [String] = []
    ) {
        self.stepID = stepID
        self.order = order
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.status = status
        self.artifactRefs = artifactRefs
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
