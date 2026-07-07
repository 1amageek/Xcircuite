import Foundation
import ToolQualification

public struct XcircuiteFlowToolSpec: Sendable, Hashable, Codable {
    public var qualificationLevel: ToolQualificationLevel
    public var healthStatus: ToolHealthStatus
    public var evidence: [ToolEvidence]

    public init(
        qualificationLevel: ToolQualificationLevel = .unknown,
        healthStatus: ToolHealthStatus = .notChecked,
        evidence: [ToolEvidence] = []
    ) {
        self.qualificationLevel = qualificationLevel
        self.healthStatus = healthStatus
        self.evidence = evidence
    }
}
