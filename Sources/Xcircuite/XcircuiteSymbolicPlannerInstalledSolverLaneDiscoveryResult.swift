import DesignFlowKernel

public struct XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult: Codable, Sendable, Hashable {
    public var lane: XcircuiteSymbolicPlannerInstalledSolverLane
    public var laneArtifact: XcircuiteFileReference

    public init(
        lane: XcircuiteSymbolicPlannerInstalledSolverLane,
        laneArtifact: XcircuiteFileReference
    ) {
        self.lane = lane
        self.laneArtifact = laneArtifact
    }
}
