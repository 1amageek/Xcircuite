import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverArtifactSet: Codable, Sendable, Hashable {
    public var runArtifact: ArtifactReference
    public var standardOutputArtifact: ArtifactReference
    public var standardErrorArtifact: ArtifactReference

    public init(
        runArtifact: ArtifactReference,
        standardOutputArtifact: ArtifactReference,
        standardErrorArtifact: ArtifactReference
    ) {
        self.runArtifact = runArtifact
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
    }
}
