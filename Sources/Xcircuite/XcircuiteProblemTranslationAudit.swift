import XcircuitePackage

public struct XcircuiteProblemTranslationAudit: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var problemPath: String
    public var sourceRefs: [XcircuitePlanningReference]
    public var translationEdges: [XcircuiteProblemTranslationAuditEdge]
    public var sourceDiagnosticCoverage: [XcircuiteProblemTranslationSourceDiagnosticCoverage]
    public var coverageSummary: XcircuiteProblemTranslationAuditCoverageSummary
    public var uncoveredSources: [XcircuiteProblemTranslationAuditIssue]
    public var uncoveredIntentClauses: [XcircuiteProblemTranslationAuditIssue]
    public var undercoveredSourceDiagnostics: [XcircuiteProblemTranslationAuditIssue]
    public var orphanObjectives: [XcircuiteProblemTranslationAuditIssue]
    public var orphanConstraints: [XcircuiteProblemTranslationAuditIssue]
    public var orphanCandidateActions: [XcircuiteProblemTranslationAuditIssue]
    public var orphanGoalAtoms: [XcircuiteProblemTranslationAuditIssue]
    public var unsupportedGoalAtoms: [XcircuiteProblemTranslationAuditIssue]
    public var diagnostics: [XcircuiteProblemTranslationAuditDiagnostic]
    public var blocking: Bool
    public var nextActions: [String]

    public init(
        status: String,
        runID: String,
        problemID: String,
        problemPath: String,
        sourceRefs: [XcircuitePlanningReference],
        translationEdges: [XcircuiteProblemTranslationAuditEdge],
        sourceDiagnosticCoverage: [XcircuiteProblemTranslationSourceDiagnosticCoverage] = [],
        coverageSummary: XcircuiteProblemTranslationAuditCoverageSummary,
        uncoveredSources: [XcircuiteProblemTranslationAuditIssue],
        uncoveredIntentClauses: [XcircuiteProblemTranslationAuditIssue] = [],
        undercoveredSourceDiagnostics: [XcircuiteProblemTranslationAuditIssue] = [],
        orphanObjectives: [XcircuiteProblemTranslationAuditIssue],
        orphanConstraints: [XcircuiteProblemTranslationAuditIssue],
        orphanCandidateActions: [XcircuiteProblemTranslationAuditIssue],
        orphanGoalAtoms: [XcircuiteProblemTranslationAuditIssue],
        unsupportedGoalAtoms: [XcircuiteProblemTranslationAuditIssue] = [],
        diagnostics: [XcircuiteProblemTranslationAuditDiagnostic],
        blocking: Bool,
        nextActions: [String]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.problemPath = problemPath
        self.sourceRefs = sourceRefs
        self.translationEdges = translationEdges
        self.sourceDiagnosticCoverage = sourceDiagnosticCoverage
        self.coverageSummary = coverageSummary
        self.uncoveredSources = uncoveredSources
        self.uncoveredIntentClauses = uncoveredIntentClauses
        self.undercoveredSourceDiagnostics = undercoveredSourceDiagnostics
        self.orphanObjectives = orphanObjectives
        self.orphanConstraints = orphanConstraints
        self.orphanCandidateActions = orphanCandidateActions
        self.orphanGoalAtoms = orphanGoalAtoms
        self.unsupportedGoalAtoms = unsupportedGoalAtoms
        self.diagnostics = diagnostics
        self.blocking = blocking
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case runID
        case problemID
        case problemPath
        case sourceRefs
        case translationEdges
        case sourceDiagnosticCoverage
        case coverageSummary
        case uncoveredSources
        case uncoveredIntentClauses
        case undercoveredSourceDiagnostics
        case orphanObjectives
        case orphanConstraints
        case orphanCandidateActions
        case orphanGoalAtoms
        case unsupportedGoalAtoms
        case diagnostics
        case blocking
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected problem translation audit schema version \(Self.currentSchemaVersion)."
            )
        }
        self.status = try container.decode(String.self, forKey: .status)
        self.runID = try container.decode(String.self, forKey: .runID)
        self.problemID = try container.decode(String.self, forKey: .problemID)
        self.problemPath = try container.decode(String.self, forKey: .problemPath)
        self.sourceRefs = try container.decode([XcircuitePlanningReference].self, forKey: .sourceRefs)
        self.translationEdges = try container.decode(
            [XcircuiteProblemTranslationAuditEdge].self,
            forKey: .translationEdges
        )
        self.sourceDiagnosticCoverage = try container.decode(
            [XcircuiteProblemTranslationSourceDiagnosticCoverage].self,
            forKey: .sourceDiagnosticCoverage
        )
        self.coverageSummary = try container.decode(
            XcircuiteProblemTranslationAuditCoverageSummary.self,
            forKey: .coverageSummary
        )
        self.uncoveredSources = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .uncoveredSources
        )
        self.uncoveredIntentClauses = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .uncoveredIntentClauses
        )
        self.undercoveredSourceDiagnostics = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .undercoveredSourceDiagnostics
        )
        self.orphanObjectives = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .orphanObjectives
        )
        self.orphanConstraints = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .orphanConstraints
        )
        self.orphanCandidateActions = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .orphanCandidateActions
        )
        self.orphanGoalAtoms = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .orphanGoalAtoms
        )
        self.unsupportedGoalAtoms = try container.decode(
            [XcircuiteProblemTranslationAuditIssue].self,
            forKey: .unsupportedGoalAtoms
        )
        self.diagnostics = try container.decode(
            [XcircuiteProblemTranslationAuditDiagnostic].self,
            forKey: .diagnostics
        )
        self.blocking = try container.decode(Bool.self, forKey: .blocking)
        self.nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encode(runID, forKey: .runID)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(problemPath, forKey: .problemPath)
        try container.encode(sourceRefs, forKey: .sourceRefs)
        try container.encode(translationEdges, forKey: .translationEdges)
        try container.encode(sourceDiagnosticCoverage, forKey: .sourceDiagnosticCoverage)
        try container.encode(coverageSummary, forKey: .coverageSummary)
        try container.encode(uncoveredSources, forKey: .uncoveredSources)
        try container.encode(uncoveredIntentClauses, forKey: .uncoveredIntentClauses)
        try container.encode(undercoveredSourceDiagnostics, forKey: .undercoveredSourceDiagnostics)
        try container.encode(orphanObjectives, forKey: .orphanObjectives)
        try container.encode(orphanConstraints, forKey: .orphanConstraints)
        try container.encode(orphanCandidateActions, forKey: .orphanCandidateActions)
        try container.encode(orphanGoalAtoms, forKey: .orphanGoalAtoms)
        try container.encode(unsupportedGoalAtoms, forKey: .unsupportedGoalAtoms)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(blocking, forKey: .blocking)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
