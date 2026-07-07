import Foundation

public struct XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var auditID: String
    public var minimumReportCount: Int
    public var requiredFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
    public var requiredSuggestedActionKinds: [String]
    public var requiredEvidenceArtifactIDs: [String]
    public var requireDiagnosticCodes: Bool

    public init(
        schemaVersion: Int = 1,
        auditID: String,
        minimumReportCount: Int = 1,
        requiredFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily] = [],
        requiredSuggestedActionKinds: [String] = [],
        requiredEvidenceArtifactIDs: [String] = [],
        requireDiagnosticCodes: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.auditID = auditID
        self.minimumReportCount = minimumReportCount
        self.requiredFirstFailingFamilies = requiredFirstFailingFamilies
        self.requiredSuggestedActionKinds = requiredSuggestedActionKinds
        self.requiredEvidenceArtifactIDs = requiredEvidenceArtifactIDs
        self.requireDiagnosticCodes = requireDiagnosticCodes
    }
}
