import Foundation
import DesignFlowKernel

public struct XcircuitePlanningCandidateAction: Codable, Sendable, Hashable {
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var maturity: String
    public var reason: String
    public var sourceObjectiveIDs: [String]
    public var requiredInputRefs: [String]
    public var verificationGates: [String]
    public var parameterHints: [String: PlanningParameterValue]

    public init(
        actionID: String,
        domainID: String,
        operationID: String,
        maturity: String,
        reason: String,
        sourceObjectiveIDs: [String],
        requiredInputRefs: [String],
        verificationGates: [String],
        parameterHints: [String: PlanningParameterValue] = [:]
    ) {
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.maturity = maturity
        self.reason = reason
        self.sourceObjectiveIDs = sourceObjectiveIDs
        self.requiredInputRefs = requiredInputRefs
        self.verificationGates = verificationGates
        self.parameterHints = parameterHints
    }
}
