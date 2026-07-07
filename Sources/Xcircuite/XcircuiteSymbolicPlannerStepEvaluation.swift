import Foundation

public struct XcircuiteSymbolicPlannerStepEvaluation: Codable, Sendable, Hashable {
    public var domainID: String
    public var operationID: String
    public var actionDomainSupported: Bool
    public var operationSupported: Bool
    public var operationMaturity: String?
    public var operationReversible: Bool?
    public var stepRequiredInputRefs: [String]
    public var stepMissingInputRefs: [String]
    public var operationInputRefs: [String]
    public var optionalOperationInputRefs: [String]
    public var boundOperationInputRefs: [String]
    public var unboundOperationInputRefs: [String]
    public var preconditions: [String]
    public var satisfiedPreconditions: [String]
    public var unsatisfiedPreconditions: [String]
    public var effects: [String]
    public var appliedEffects: [String]
    public var producedArtifacts: [String]
    public var verificationGates: [String]
    public var stateBefore: [String]
    public var stateAfter: [String]
    public var bindingStatus: String

    public init(
        domainID: String,
        operationID: String,
        actionDomainSupported: Bool,
        operationSupported: Bool,
        operationMaturity: String? = nil,
        operationReversible: Bool? = nil,
        stepRequiredInputRefs: [String],
        stepMissingInputRefs: [String],
        operationInputRefs: [String] = [],
        optionalOperationInputRefs: [String] = [],
        boundOperationInputRefs: [String] = [],
        unboundOperationInputRefs: [String] = [],
        preconditions: [String] = [],
        satisfiedPreconditions: [String] = [],
        unsatisfiedPreconditions: [String] = [],
        effects: [String] = [],
        appliedEffects: [String] = [],
        producedArtifacts: [String] = [],
        verificationGates: [String] = [],
        stateBefore: [String] = [],
        stateAfter: [String] = [],
        bindingStatus: String
    ) {
        self.domainID = domainID
        self.operationID = operationID
        self.actionDomainSupported = actionDomainSupported
        self.operationSupported = operationSupported
        self.operationMaturity = operationMaturity
        self.operationReversible = operationReversible
        self.stepRequiredInputRefs = stepRequiredInputRefs
        self.stepMissingInputRefs = stepMissingInputRefs
        self.operationInputRefs = operationInputRefs
        self.optionalOperationInputRefs = optionalOperationInputRefs
        self.boundOperationInputRefs = boundOperationInputRefs
        self.unboundOperationInputRefs = unboundOperationInputRefs
        self.preconditions = preconditions
        self.satisfiedPreconditions = satisfiedPreconditions
        self.unsatisfiedPreconditions = unsatisfiedPreconditions
        self.effects = effects
        self.appliedEffects = appliedEffects
        self.producedArtifacts = producedArtifacts
        self.verificationGates = verificationGates
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.bindingStatus = bindingStatus
    }
}
