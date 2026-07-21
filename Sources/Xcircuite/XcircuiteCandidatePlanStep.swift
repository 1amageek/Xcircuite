import Foundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanStep: Codable, Sendable, Hashable {
    public var stepID: String
    public var order: Int
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var maturity: XcircuiteOperationMaturity
    public var readiness: String
    public var sourceObjectiveIDs: [String]
    public var requiredInputRefs: [String]
    public var missingInputRefs: [String]
    public var verificationGates: [String]
    public var reason: String
    public var parameterHints: [String: PlanningParameterValue]
    public var blockers: [String]

    public init(
        stepID: String,
        order: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        maturity: XcircuiteOperationMaturity,
        readiness: String,
        sourceObjectiveIDs: [String],
        requiredInputRefs: [String],
        missingInputRefs: [String],
        verificationGates: [String],
        reason: String,
        parameterHints: [String: PlanningParameterValue],
        blockers: [String]
    ) {
        self.stepID = stepID
        self.order = order
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.maturity = maturity
        self.readiness = readiness
        self.sourceObjectiveIDs = sourceObjectiveIDs
        self.requiredInputRefs = requiredInputRefs
        self.missingInputRefs = missingInputRefs
        self.verificationGates = verificationGates
        self.reason = reason
        self.parameterHints = parameterHints
        self.blockers = blockers
    }
}
