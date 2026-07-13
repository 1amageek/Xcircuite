import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyBatchResult: Codable, Sendable, Hashable {
    public var batchRun: XcircuiteSymbolicPlannerSolverFamilyBatchRun
    public var batchArtifact: ArtifactReference
    public var comparisonResult: XcircuiteSymbolicPlannerSolverFamilyComparisonResult
    public var promotionResult: XcircuiteSymbolicPlannerSolverFamilyPromotionResult?

    public init(
        batchRun: XcircuiteSymbolicPlannerSolverFamilyBatchRun,
        batchArtifact: ArtifactReference,
        comparisonResult: XcircuiteSymbolicPlannerSolverFamilyComparisonResult,
        promotionResult: XcircuiteSymbolicPlannerSolverFamilyPromotionResult?
    ) {
        self.batchRun = batchRun
        self.batchArtifact = batchArtifact
        self.comparisonResult = comparisonResult
        self.promotionResult = promotionResult
    }
}
