import DesignFlowKernel

public struct XcircuiteSymbolicPlannerProofValidationArtifactSet: Codable, Sendable, Hashable {
    public var validationArtifact: XcircuiteFileReference
    public var standardOutputArtifact: XcircuiteFileReference
    public var standardErrorArtifact: XcircuiteFileReference

    public init(
        validationArtifact: XcircuiteFileReference,
        standardOutputArtifact: XcircuiteFileReference,
        standardErrorArtifact: XcircuiteFileReference
    ) {
        self.validationArtifact = validationArtifact
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
    }
}
