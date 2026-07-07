import XcircuitePackage

public struct XcircuiteSymbolicPlannerSolverFamilyPromotionResult: Codable, Sendable, Hashable {
    public var promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion
    public var promotionArtifact: XcircuiteFileReference

    public init(
        promotion: XcircuiteSymbolicPlannerSolverFamilyPromotion,
        promotionArtifact: XcircuiteFileReference
    ) {
        self.promotion = promotion
        self.promotionArtifact = promotionArtifact
    }
}
