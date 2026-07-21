public struct XcircuiteActionDomainOperation: Codable, Sendable, Hashable {
    public var operationID: String
    public var maturity: XcircuiteOperationMaturity
    public var inputRefs: [String]
    public var preconditions: [String]
    public var effects: [String]
    public var producedArtifacts: [String]
    public var verificationGates: [String]
    public var reversible: Bool

    public init(
        operationID: String,
        maturity: XcircuiteOperationMaturity,
        inputRefs: [String],
        preconditions: [String],
        effects: [String],
        producedArtifacts: [String],
        verificationGates: [String],
        reversible: Bool
    ) {
        self.operationID = operationID
        self.maturity = maturity
        self.inputRefs = inputRefs
        self.preconditions = preconditions
        self.effects = effects
        self.producedArtifacts = producedArtifacts
        self.verificationGates = verificationGates
        self.reversible = reversible
    }
}
