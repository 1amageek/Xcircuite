import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyComparisonResult: Codable, Sendable, Hashable {
    public var comparison: XcircuiteSymbolicPlannerSolverFamilyComparison
    public var comparisonArtifact: ArtifactReference

    public init(
        comparison: XcircuiteSymbolicPlannerSolverFamilyComparison,
        comparisonArtifact: ArtifactReference
    ) {
        self.comparison = comparison
        self.comparisonArtifact = comparisonArtifact
    }
}
