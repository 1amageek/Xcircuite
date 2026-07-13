import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerProofValidationArtifactSet: Codable, Sendable, Hashable {
    public var validationArtifact: ArtifactReference
    public var standardOutputArtifact: ArtifactReference
    public var standardErrorArtifact: ArtifactReference

    public init(
        validationArtifact: ArtifactReference,
        standardOutputArtifact: ArtifactReference,
        standardErrorArtifact: ArtifactReference
    ) {
        self.validationArtifact = validationArtifact
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
    }
}
