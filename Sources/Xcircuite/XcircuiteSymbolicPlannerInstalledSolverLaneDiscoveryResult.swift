import DesignFlowKernel

public struct XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult: Codable, Sendable, Hashable {
    public var lane: XcircuiteSymbolicPlannerInstalledSolverLane
    public var laneArtifact: ArtifactReference

    public init(
        lane: XcircuiteSymbolicPlannerInstalledSolverLane,
        laneArtifact: ArtifactReference
    ) {
        self.lane = lane
        self.laneArtifact = laneArtifact
    }
}
