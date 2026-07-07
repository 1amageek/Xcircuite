public struct XcircuiteSymbolicPlannerPlanReplayValidation: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var validationStrategy: String
    public var initialAtoms: [String]
    public var goalAtoms: [String]
    public var finalAtoms: [String]
    public var missingGoalAtoms: [String]
    public var evaluatedCost: Double
    public var evaluatedCostUnit: String
    public var steps: [XcircuiteSymbolicPlannerPlanReplayStepValidation]
    public var diagnostics: [XcircuiteSymbolicPlannerPlanReplayDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        planID: String,
        validationStrategy: String,
        initialAtoms: [String],
        goalAtoms: [String],
        finalAtoms: [String],
        missingGoalAtoms: [String],
        evaluatedCost: Double,
        evaluatedCostUnit: String,
        steps: [XcircuiteSymbolicPlannerPlanReplayStepValidation],
        diagnostics: [XcircuiteSymbolicPlannerPlanReplayDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.validationStrategy = validationStrategy
        self.initialAtoms = initialAtoms
        self.goalAtoms = goalAtoms
        self.finalAtoms = finalAtoms
        self.missingGoalAtoms = missingGoalAtoms
        self.evaluatedCost = evaluatedCost
        self.evaluatedCostUnit = evaluatedCostUnit
        self.steps = steps
        self.diagnostics = diagnostics
    }
}
