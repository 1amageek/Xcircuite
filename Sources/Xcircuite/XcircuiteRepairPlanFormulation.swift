import Foundation
import DesignFlowKernel

public struct XcircuiteRepairPlanFormulation: Codable, Sendable, Hashable {
    public struct Goal: Codable, Sendable, Hashable {
        public var goalID: String
        public var kind: String
        public var domain: String
        public var priority: String
        public var sourceRefIDs: [String]
        public var target: String
        public var currentValue: PlanningParameterValue?
        public var requiredValue: PlanningParameterValue?
        public var unit: String?
        public var description: String
        public var symbolicGoalAtoms: [String]
        public var evidence: [String: PlanningParameterValue]
        public var suggestedActions: [String]

        public init(
            goalID: String,
            kind: String,
            domain: String,
            priority: String,
            sourceRefIDs: [String],
            target: String,
            currentValue: PlanningParameterValue? = nil,
            requiredValue: PlanningParameterValue? = nil,
            unit: String? = nil,
            description: String,
            symbolicGoalAtoms: [String] = [],
            evidence: [String: PlanningParameterValue] = [:],
            suggestedActions: [String] = []
        ) {
            self.goalID = goalID
            self.kind = kind
            self.domain = domain
            self.priority = priority
            self.sourceRefIDs = sourceRefIDs
            self.target = target
            self.currentValue = currentValue
            self.requiredValue = requiredValue
            self.unit = unit
            self.description = description
            self.symbolicGoalAtoms = symbolicGoalAtoms
            self.evidence = evidence
            self.suggestedActions = suggestedActions
        }
    }

    public struct Action: Codable, Sendable, Hashable {
        public var actionID: String
        public var domainID: String
        public var operationID: String
        public var maturity: XcircuiteOperationMaturity
        public var reason: String
        public var sourceGoalIDs: [String]
        public var requiredInputRefs: [String]
        public var verificationGates: [String]
        public var parameterHints: [String: PlanningParameterValue]

        public init(
            actionID: String,
            domainID: String,
            operationID: String,
            maturity: XcircuiteOperationMaturity,
            reason: String,
            sourceGoalIDs: [String],
            requiredInputRefs: [String],
            verificationGates: [String],
            parameterHints: [String: PlanningParameterValue] = [:]
        ) {
            self.actionID = actionID
            self.domainID = domainID
            self.operationID = operationID
            self.maturity = maturity
            self.reason = reason
            self.sourceGoalIDs = sourceGoalIDs
            self.requiredInputRefs = requiredInputRefs
            self.verificationGates = verificationGates
            self.parameterHints = parameterHints
        }
    }

    public var schemaVersion: Int
    public var formulationID: String
    public var runID: String
    public var intentID: String
    public var intent: String
    public var sourceRefs: [XcircuitePlanningReference]
    public var initialStateRefs: [XcircuitePlanningReference]
    public var assumptions: [XcircuitePlanningAssumption]
    public var riskClassifications: [XcircuitePlanningRiskClassification]
    public var goals: [Goal]
    public var constraints: [XcircuitePlanningConstraint]
    public var actionDomainRefs: [String]
    public var actions: [Action]
    public var costModel: XcircuitePlanningCostModel?
    public var verificationGates: [XcircuitePlanningVerificationGate]
    public var resumeContract: XcircuitePlanningResumeContract?
    public var metadata: [String: PlanningParameterValue]

    public init(
        schemaVersion: Int = 1,
        formulationID: String,
        runID: String,
        intentID: String,
        intent: String,
        sourceRefs: [XcircuitePlanningReference],
        initialStateRefs: [XcircuitePlanningReference],
        assumptions: [XcircuitePlanningAssumption] = [],
        riskClassifications: [XcircuitePlanningRiskClassification] = [],
        goals: [Goal],
        constraints: [XcircuitePlanningConstraint] = [],
        actionDomainRefs: [String] = [],
        actions: [Action],
        costModel: XcircuitePlanningCostModel? = nil,
        verificationGates: [XcircuitePlanningVerificationGate] = [],
        resumeContract: XcircuitePlanningResumeContract? = nil,
        metadata: [String: PlanningParameterValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.formulationID = formulationID
        self.runID = runID
        self.intentID = intentID
        self.intent = intent
        self.sourceRefs = sourceRefs
        self.initialStateRefs = initialStateRefs
        self.assumptions = assumptions
        self.riskClassifications = riskClassifications
        self.goals = goals
        self.constraints = constraints
        self.actionDomainRefs = actionDomainRefs
        self.actions = actions
        self.costModel = costModel
        self.verificationGates = verificationGates
        self.resumeContract = resumeContract
        self.metadata = metadata
    }
}
