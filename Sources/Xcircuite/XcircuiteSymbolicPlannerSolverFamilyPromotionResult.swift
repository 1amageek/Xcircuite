import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyPromotionResult: Codable, Sendable, Hashable {
    public var promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion
    public var promotionArtifact: ArtifactReference

    public init(
        promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion,
        promotionArtifact: ArtifactReference
    ) {
        self.promotion = promotion
        self.promotionArtifact = promotionArtifact
    }
}
