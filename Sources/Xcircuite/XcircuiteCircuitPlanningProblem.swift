import Foundation

public struct XcircuiteCircuitPlanningProblem: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var problemID: String
    public var runID: String
    public var sourceRefs: [XcircuitePlanningReference]
    public var initialStateRefs: [XcircuitePlanningReference]
    public var assumptions: [XcircuitePlanningAssumption]
    public var riskClassifications: [XcircuitePlanningRiskClassification]
    public var objectives: [XcircuitePlanningObjective]
    public var constraints: [XcircuitePlanningConstraint]
    public var actionDomainRefs: [String]
    public var candidateActions: [XcircuitePlanningCandidateAction]
    public var costModel: XcircuitePlanningCostModel
    public var verificationGates: [XcircuitePlanningVerificationGate]
    public var resumeContract: XcircuitePlanningResumeContract

    public init(
        schemaVersion: Int = 1,
        problemID: String,
        runID: String,
        sourceRefs: [XcircuitePlanningReference],
        initialStateRefs: [XcircuitePlanningReference],
        assumptions: [XcircuitePlanningAssumption] = [],
        riskClassifications: [XcircuitePlanningRiskClassification] = [],
        objectives: [XcircuitePlanningObjective],
        constraints: [XcircuitePlanningConstraint],
        actionDomainRefs: [String],
        candidateActions: [XcircuitePlanningCandidateAction],
        costModel: XcircuitePlanningCostModel,
        verificationGates: [XcircuitePlanningVerificationGate],
        resumeContract: XcircuitePlanningResumeContract
    ) {
        self.schemaVersion = schemaVersion
        self.problemID = problemID
        self.runID = runID
        self.sourceRefs = sourceRefs
        self.initialStateRefs = initialStateRefs
        self.assumptions = assumptions
        self.riskClassifications = riskClassifications
        self.objectives = objectives
        self.constraints = constraints
        self.actionDomainRefs = actionDomainRefs
        self.candidateActions = candidateActions
        self.costModel = costModel
        self.verificationGates = verificationGates
        self.resumeContract = resumeContract
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case problemID
        case runID
        case sourceRefs
        case initialStateRefs
        case assumptions
        case riskClassifications
        case objectives
        case constraints
        case actionDomainRefs
        case candidateActions
        case costModel
        case verificationGates
        case resumeContract
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        problemID = try container.decode(String.self, forKey: .problemID)
        runID = try container.decode(String.self, forKey: .runID)
        sourceRefs = try container.decode([XcircuitePlanningReference].self, forKey: .sourceRefs)
        initialStateRefs = try container.decode([XcircuitePlanningReference].self, forKey: .initialStateRefs)
        assumptions = try container.decodeIfPresent([XcircuitePlanningAssumption].self, forKey: .assumptions) ?? []
        riskClassifications = try container.decodeIfPresent(
            [XcircuitePlanningRiskClassification].self,
            forKey: .riskClassifications
        ) ?? []
        objectives = try container.decode([XcircuitePlanningObjective].self, forKey: .objectives)
        constraints = try container.decode([XcircuitePlanningConstraint].self, forKey: .constraints)
        actionDomainRefs = try container.decode([String].self, forKey: .actionDomainRefs)
        candidateActions = try container.decode([XcircuitePlanningCandidateAction].self, forKey: .candidateActions)
        costModel = try container.decode(XcircuitePlanningCostModel.self, forKey: .costModel)
        verificationGates = try container.decode([XcircuitePlanningVerificationGate].self, forKey: .verificationGates)
        resumeContract = try container.decode(XcircuitePlanningResumeContract.self, forKey: .resumeContract)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(runID, forKey: .runID)
        try container.encode(sourceRefs, forKey: .sourceRefs)
        try container.encode(initialStateRefs, forKey: .initialStateRefs)
        try container.encode(assumptions, forKey: .assumptions)
        try container.encode(riskClassifications, forKey: .riskClassifications)
        try container.encode(objectives, forKey: .objectives)
        try container.encode(constraints, forKey: .constraints)
        try container.encode(actionDomainRefs, forKey: .actionDomainRefs)
        try container.encode(candidateActions, forKey: .candidateActions)
        try container.encode(costModel, forKey: .costModel)
        try container.encode(verificationGates, forKey: .verificationGates)
        try container.encode(resumeContract, forKey: .resumeContract)
    }
}
