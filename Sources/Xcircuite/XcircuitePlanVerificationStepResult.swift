import Foundation
import DesignFlowKernel

public struct XcircuitePlanVerificationStepResult: Codable, Sendable, Hashable {
    public var stepID: String
    public var order: Int
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var status: String
    public var gateIDs: [String]
    public var symbolicEvaluation: XcircuiteSymbolicPlannerStepEvaluation?
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var producedArtifactRefs: [ArtifactReference]

    public init(
        stepID: String,
        order: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        status: String,
        gateIDs: [String],
        symbolicEvaluation: XcircuiteSymbolicPlannerStepEvaluation? = nil,
        diagnostics: [XcircuitePlanVerificationDiagnostic] = [],
        producedArtifactRefs: [ArtifactReference] = []
    ) {
        self.stepID = stepID
        self.order = order
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.status = status
        self.gateIDs = gateIDs
        self.symbolicEvaluation = symbolicEvaluation
        self.diagnostics = diagnostics
        self.producedArtifactRefs = producedArtifactRefs
    }
}
