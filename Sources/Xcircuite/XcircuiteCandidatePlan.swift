import Foundation

public struct XcircuiteCandidatePlan: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var planID: String
    public var problemID: String
    public var runID: String
    public var strategy: String
    public var executionReadiness: String
    public var sourceProblemRef: XcircuitePlanningReference
    public var assumptions: [XcircuitePlanningAssumption]
    public var riskClassifications: [XcircuitePlanningRiskClassification]
    public var steps: [XcircuiteCandidatePlanStep]
    public var verificationGates: [XcircuitePlanningVerificationGate]
    public var constraints: [XcircuitePlanningConstraint]
    public var unresolvedObjectives: [String]
    public var blockers: [String]

    public init(
        schemaVersion: Int = 1,
        planID: String,
        problemID: String,
        runID: String,
        strategy: String,
        executionReadiness: String,
        sourceProblemRef: XcircuitePlanningReference,
        assumptions: [XcircuitePlanningAssumption] = [],
        riskClassifications: [XcircuitePlanningRiskClassification] = [],
        steps: [XcircuiteCandidatePlanStep],
        verificationGates: [XcircuitePlanningVerificationGate],
        constraints: [XcircuitePlanningConstraint],
        unresolvedObjectives: [String],
        blockers: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.planID = planID
        self.problemID = problemID
        self.runID = runID
        self.strategy = strategy
        self.executionReadiness = executionReadiness
        self.sourceProblemRef = sourceProblemRef
        self.assumptions = assumptions
        self.riskClassifications = riskClassifications
        self.steps = steps
        self.verificationGates = verificationGates
        self.constraints = constraints
        self.unresolvedObjectives = unresolvedObjectives
        self.blockers = blockers
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case planID
        case problemID
        case runID
        case strategy
        case executionReadiness
        case sourceProblemRef
        case assumptions
        case riskClassifications
        case steps
        case verificationGates
        case constraints
        case unresolvedObjectives
        case blockers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported candidate plan schema version: \(schemaVersion)."
            )
        }
        planID = try container.decode(String.self, forKey: .planID)
        problemID = try container.decode(String.self, forKey: .problemID)
        runID = try container.decode(String.self, forKey: .runID)
        strategy = try container.decode(String.self, forKey: .strategy)
        executionReadiness = try container.decode(String.self, forKey: .executionReadiness)
        sourceProblemRef = try container.decode(XcircuitePlanningReference.self, forKey: .sourceProblemRef)
        assumptions = try container.decode([XcircuitePlanningAssumption].self, forKey: .assumptions)
        riskClassifications = try container.decode(
            [XcircuitePlanningRiskClassification].self,
            forKey: .riskClassifications
        )
        steps = try container.decode([XcircuiteCandidatePlanStep].self, forKey: .steps)
        verificationGates = try container.decode([XcircuitePlanningVerificationGate].self, forKey: .verificationGates)
        constraints = try container.decode([XcircuitePlanningConstraint].self, forKey: .constraints)
        unresolvedObjectives = try container.decode([String].self, forKey: .unresolvedObjectives)
        blockers = try container.decode([String].self, forKey: .blockers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(planID, forKey: .planID)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(runID, forKey: .runID)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(executionReadiness, forKey: .executionReadiness)
        try container.encode(sourceProblemRef, forKey: .sourceProblemRef)
        try container.encode(assumptions, forKey: .assumptions)
        try container.encode(riskClassifications, forKey: .riskClassifications)
        try container.encode(steps, forKey: .steps)
        try container.encode(verificationGates, forKey: .verificationGates)
        try container.encode(constraints, forKey: .constraints)
        try container.encode(unresolvedObjectives, forKey: .unresolvedObjectives)
        try container.encode(blockers, forKey: .blockers)
    }
}
