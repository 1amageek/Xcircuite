public struct XcircuiteProblemTranslationSourceDiagnosticCoverage: Codable, Sendable, Hashable {
    public var sourceRefID: String
    public var sourceKind: String
    public var status: String
    public var objectiveIDs: [String]
    public var constraintIDs: [String]
    public var candidateActionIDs: [String]
    public var verificationGateIDs: [String]
    public var missingTargetKinds: [String]

    public init(
        sourceRefID: String,
        sourceKind: String,
        status: String,
        objectiveIDs: [String] = [],
        constraintIDs: [String] = [],
        candidateActionIDs: [String] = [],
        verificationGateIDs: [String] = [],
        missingTargetKinds: [String] = []
    ) {
        self.sourceRefID = sourceRefID
        self.sourceKind = sourceKind
        self.status = status
        self.objectiveIDs = objectiveIDs
        self.constraintIDs = constraintIDs
        self.candidateActionIDs = candidateActionIDs
        self.verificationGateIDs = verificationGateIDs
        self.missingTargetKinds = missingTargetKinds
    }
}
