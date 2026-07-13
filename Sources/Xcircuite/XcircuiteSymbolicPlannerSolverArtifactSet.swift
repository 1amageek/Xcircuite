import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverArtifactSet: Codable, Sendable, Hashable {
    public var runArtifact: XcircuiteFileReference
    public var standardOutputArtifact: XcircuiteFileReference
    public var standardErrorArtifact: XcircuiteFileReference

    public init(
        runArtifact: XcircuiteFileReference,
        standardOutputArtifact: XcircuiteFileReference,
        standardErrorArtifact: XcircuiteFileReference
    ) {
        self.runArtifact = runArtifact
        self.standardOutputArtifact = standardOutputArtifact
        self.standardErrorArtifact = standardErrorArtifact
    }
}
