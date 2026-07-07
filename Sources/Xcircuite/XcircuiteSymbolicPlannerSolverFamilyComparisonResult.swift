import XcircuitePackage

public struct XcircuiteSymbolicPlannerSolverFamilyComparisonResult: Codable, Sendable, Hashable {
    public var comparison: XcircuiteSymbolicPlannerSolverFamilyComparison
    public var comparisonArtifact: XcircuiteFileReference

    public init(
        comparison: XcircuiteSymbolicPlannerSolverFamilyComparison,
        comparisonArtifact: XcircuiteFileReference
    ) {
        self.comparison = comparison
        self.comparisonArtifact = comparisonArtifact
    }
}
