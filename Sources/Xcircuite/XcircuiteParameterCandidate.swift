import Foundation

public struct XcircuiteParameterCandidate: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var candidateID: String
    public var runID: String
    public var problemID: String
    public var rank: Int
    public var sourceActionID: String
    public var sourceOperationID: String
    public var sourceObjectiveIDs: [String]
    public var assignments: [XcircuiteParameterAssignment]
    public var normalizedCost: Double
    public var verificationGates: [String]
    public var rationale: String
    public var diagnostics: [XcircuiteParameterCandidateDiagnostic]

    public init(
        schemaVersion: Int = 1,
        candidateID: String,
        runID: String,
        problemID: String,
        rank: Int,
        sourceActionID: String,
        sourceOperationID: String,
        sourceObjectiveIDs: [String],
        assignments: [XcircuiteParameterAssignment],
        normalizedCost: Double,
        verificationGates: [String],
        rationale: String,
        diagnostics: [XcircuiteParameterCandidateDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.candidateID = candidateID
        self.runID = runID
        self.problemID = problemID
        self.rank = rank
        self.sourceActionID = sourceActionID
        self.sourceOperationID = sourceOperationID
        self.sourceObjectiveIDs = sourceObjectiveIDs
        self.assignments = assignments
        self.normalizedCost = normalizedCost
        self.verificationGates = verificationGates
        self.rationale = rationale
        self.diagnostics = diagnostics
    }
}
