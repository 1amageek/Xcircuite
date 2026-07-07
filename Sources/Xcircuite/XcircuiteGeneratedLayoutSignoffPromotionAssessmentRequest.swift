import Foundation

public struct XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var promotionID: String
    public var requiredExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
    public var requireGeneratedLayoutOracleReady: Bool
    public var requireRetainedExternalOracleSuite: Bool

    public init(
        schemaVersion: Int = 1,
        promotionID: String = "generated-layout-signoff-promotion",
        requiredExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily] = [.drc, .lvs, .pex],
        requireGeneratedLayoutOracleReady: Bool = true,
        requireRetainedExternalOracleSuite: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.promotionID = promotionID
        self.requiredExternalOracleDomains = requiredExternalOracleDomains
        self.requireGeneratedLayoutOracleReady = requireGeneratedLayoutOracleReady
        self.requireRetainedExternalOracleSuite = requireRetainedExternalOracleSuite
    }
}
