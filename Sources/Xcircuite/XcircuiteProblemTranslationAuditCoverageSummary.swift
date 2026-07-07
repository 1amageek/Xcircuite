public struct XcircuiteProblemTranslationAuditCoverageSummary: Codable, Sendable, Hashable {
    public var sourceRefCount: Int
    public var coveredSourceRefCount: Int
    public var uncoveredSourceRefCount: Int
    public var intentClauseCount: Int
    public var uncoveredIntentClauseCount: Int
    public var objectiveCount: Int
    public var orphanObjectiveCount: Int
    public var constraintCount: Int
    public var orphanConstraintCount: Int
    public var candidateActionCount: Int
    public var orphanCandidateActionCount: Int
    public var goalAtomCount: Int
    public var orphanGoalAtomCount: Int
    public var unsupportedGoalAtomCount: Int
    public var translationEdgeCount: Int
    public var sourceDiagnosticRefCount: Int
    public var fullyCoveredSourceDiagnosticCount: Int
    public var undercoveredSourceDiagnosticCount: Int

    public init(
        sourceRefCount: Int,
        coveredSourceRefCount: Int,
        uncoveredSourceRefCount: Int,
        intentClauseCount: Int = 0,
        uncoveredIntentClauseCount: Int = 0,
        objectiveCount: Int,
        orphanObjectiveCount: Int,
        constraintCount: Int,
        orphanConstraintCount: Int,
        candidateActionCount: Int,
        orphanCandidateActionCount: Int,
        goalAtomCount: Int,
        orphanGoalAtomCount: Int,
        unsupportedGoalAtomCount: Int = 0,
        translationEdgeCount: Int,
        sourceDiagnosticRefCount: Int = 0,
        fullyCoveredSourceDiagnosticCount: Int = 0,
        undercoveredSourceDiagnosticCount: Int = 0
    ) {
        self.sourceRefCount = sourceRefCount
        self.coveredSourceRefCount = coveredSourceRefCount
        self.uncoveredSourceRefCount = uncoveredSourceRefCount
        self.intentClauseCount = intentClauseCount
        self.uncoveredIntentClauseCount = uncoveredIntentClauseCount
        self.objectiveCount = objectiveCount
        self.orphanObjectiveCount = orphanObjectiveCount
        self.constraintCount = constraintCount
        self.orphanConstraintCount = orphanConstraintCount
        self.candidateActionCount = candidateActionCount
        self.orphanCandidateActionCount = orphanCandidateActionCount
        self.goalAtomCount = goalAtomCount
        self.orphanGoalAtomCount = orphanGoalAtomCount
        self.unsupportedGoalAtomCount = unsupportedGoalAtomCount
        self.translationEdgeCount = translationEdgeCount
        self.sourceDiagnosticRefCount = sourceDiagnosticRefCount
        self.fullyCoveredSourceDiagnosticCount = fullyCoveredSourceDiagnosticCount
        self.undercoveredSourceDiagnosticCount = undercoveredSourceDiagnosticCount
    }

    private enum CodingKeys: String, CodingKey {
        case sourceRefCount
        case coveredSourceRefCount
        case uncoveredSourceRefCount
        case intentClauseCount
        case uncoveredIntentClauseCount
        case objectiveCount
        case orphanObjectiveCount
        case constraintCount
        case orphanConstraintCount
        case candidateActionCount
        case orphanCandidateActionCount
        case goalAtomCount
        case orphanGoalAtomCount
        case unsupportedGoalAtomCount
        case translationEdgeCount
        case sourceDiagnosticRefCount
        case fullyCoveredSourceDiagnosticCount
        case undercoveredSourceDiagnosticCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceRefCount = try container.decode(Int.self, forKey: .sourceRefCount)
        self.coveredSourceRefCount = try container.decode(Int.self, forKey: .coveredSourceRefCount)
        self.uncoveredSourceRefCount = try container.decode(Int.self, forKey: .uncoveredSourceRefCount)
        self.intentClauseCount = try container.decodeIfPresent(Int.self, forKey: .intentClauseCount) ?? 0
        self.uncoveredIntentClauseCount = try container.decodeIfPresent(
            Int.self,
            forKey: .uncoveredIntentClauseCount
        ) ?? 0
        self.objectiveCount = try container.decode(Int.self, forKey: .objectiveCount)
        self.orphanObjectiveCount = try container.decode(Int.self, forKey: .orphanObjectiveCount)
        self.constraintCount = try container.decode(Int.self, forKey: .constraintCount)
        self.orphanConstraintCount = try container.decode(Int.self, forKey: .orphanConstraintCount)
        self.candidateActionCount = try container.decode(Int.self, forKey: .candidateActionCount)
        self.orphanCandidateActionCount = try container.decode(Int.self, forKey: .orphanCandidateActionCount)
        self.goalAtomCount = try container.decode(Int.self, forKey: .goalAtomCount)
        self.orphanGoalAtomCount = try container.decode(Int.self, forKey: .orphanGoalAtomCount)
        self.unsupportedGoalAtomCount = try container.decodeIfPresent(
            Int.self,
            forKey: .unsupportedGoalAtomCount
        ) ?? 0
        self.translationEdgeCount = try container.decode(Int.self, forKey: .translationEdgeCount)
        self.sourceDiagnosticRefCount = try container.decodeIfPresent(
            Int.self,
            forKey: .sourceDiagnosticRefCount
        ) ?? 0
        self.fullyCoveredSourceDiagnosticCount = try container.decodeIfPresent(
            Int.self,
            forKey: .fullyCoveredSourceDiagnosticCount
        ) ?? 0
        self.undercoveredSourceDiagnosticCount = try container.decodeIfPresent(
            Int.self,
            forKey: .undercoveredSourceDiagnosticCount
        ) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceRefCount, forKey: .sourceRefCount)
        try container.encode(coveredSourceRefCount, forKey: .coveredSourceRefCount)
        try container.encode(uncoveredSourceRefCount, forKey: .uncoveredSourceRefCount)
        try container.encode(intentClauseCount, forKey: .intentClauseCount)
        try container.encode(uncoveredIntentClauseCount, forKey: .uncoveredIntentClauseCount)
        try container.encode(objectiveCount, forKey: .objectiveCount)
        try container.encode(orphanObjectiveCount, forKey: .orphanObjectiveCount)
        try container.encode(constraintCount, forKey: .constraintCount)
        try container.encode(orphanConstraintCount, forKey: .orphanConstraintCount)
        try container.encode(candidateActionCount, forKey: .candidateActionCount)
        try container.encode(orphanCandidateActionCount, forKey: .orphanCandidateActionCount)
        try container.encode(goalAtomCount, forKey: .goalAtomCount)
        try container.encode(orphanGoalAtomCount, forKey: .orphanGoalAtomCount)
        try container.encode(unsupportedGoalAtomCount, forKey: .unsupportedGoalAtomCount)
        try container.encode(translationEdgeCount, forKey: .translationEdgeCount)
        try container.encode(sourceDiagnosticRefCount, forKey: .sourceDiagnosticRefCount)
        try container.encode(fullyCoveredSourceDiagnosticCount, forKey: .fullyCoveredSourceDiagnosticCount)
        try container.encode(undercoveredSourceDiagnosticCount, forKey: .undercoveredSourceDiagnosticCount)
    }
}
