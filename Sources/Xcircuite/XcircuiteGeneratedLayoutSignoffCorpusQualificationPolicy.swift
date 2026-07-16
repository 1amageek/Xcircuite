import Foundation

public struct XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var policyID: String
    public var minimumCaseCount: Int
    public var requiredCoverageTags: [String]
    public var requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
    public var requiredOracleReadinessFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
    public var acceptedOracleReadinessStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus]
    public var requireReportPassed: Bool
    public var requireArtifactHashes: Bool
    public var requireArtifactByteCounts: Bool
    public var requireArtifactIntegrityPassed: Bool
    public var requireReadyOracleEvidenceRefs: Bool
    public var requireReadyOracleEvidenceHashes: Bool
    public var requireReadyOracleEvidenceByteCounts: Bool
    public var allowExpectedVerdictMismatches: Bool
    public var minimumSourceArtifactCount: Int
    public var minimumSignoffArtifactCount: Int

    public init(
        schemaVersion: Int = 1,
        policyID: String = "generated-layout-signoff-corpus-production-gate",
        minimumCaseCount: Int = 1,
        requiredCoverageTags: [String] = [],
        requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily] = [.layout, .drc, .lvs, .pex],
        requiredOracleReadinessFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily] = [.drc, .lvs, .pex],
        acceptedOracleReadinessStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus] = [.ready],
        requireReportPassed: Bool = true,
        requireArtifactHashes: Bool = true,
        requireArtifactByteCounts: Bool = true,
        requireArtifactIntegrityPassed: Bool = true,
        requireReadyOracleEvidenceRefs: Bool = true,
        requireReadyOracleEvidenceHashes: Bool = true,
        requireReadyOracleEvidenceByteCounts: Bool = true,
        allowExpectedVerdictMismatches: Bool = false,
        minimumSourceArtifactCount: Int = 1,
        minimumSignoffArtifactCount: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.minimumCaseCount = minimumCaseCount
        self.requiredCoverageTags = requiredCoverageTags
        self.requiredStageFamilies = requiredStageFamilies
        self.requiredOracleReadinessFamilies = requiredOracleReadinessFamilies
        self.acceptedOracleReadinessStatuses = acceptedOracleReadinessStatuses
        self.requireReportPassed = requireReportPassed
        self.requireArtifactHashes = requireArtifactHashes
        self.requireArtifactByteCounts = requireArtifactByteCounts
        self.requireArtifactIntegrityPassed = requireArtifactIntegrityPassed
        self.requireReadyOracleEvidenceRefs = requireReadyOracleEvidenceRefs
        self.requireReadyOracleEvidenceHashes = requireReadyOracleEvidenceHashes
        self.requireReadyOracleEvidenceByteCounts = requireReadyOracleEvidenceByteCounts
        self.allowExpectedVerdictMismatches = allowExpectedVerdictMismatches
        self.minimumSourceArtifactCount = minimumSourceArtifactCount
        self.minimumSignoffArtifactCount = minimumSignoffArtifactCount
    }

    public static func defaultPolicy(
        requiredCoverageTags: [String]
    ) -> XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy {
        XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy(
            requiredCoverageTags: requiredCoverageTags
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case policyID
        case minimumCaseCount
        case requiredCoverageTags
        case requiredStageFamilies
        case requiredOracleReadinessFamilies
        case acceptedOracleReadinessStatuses
        case requireReportPassed
        case requireArtifactHashes
        case requireArtifactByteCounts
        case requireArtifactIntegrityPassed
        case requireReadyOracleEvidenceRefs
        case requireReadyOracleEvidenceHashes
        case requireReadyOracleEvidenceByteCounts
        case allowExpectedVerdictMismatches
        case minimumSourceArtifactCount
        case minimumSignoffArtifactCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported generated-layout signoff corpus qualification policy schema version: \(schemaVersion)."
            )
        }
        self.policyID = try container.decodeIfPresent(
            String.self,
            forKey: .policyID
        ) ?? "generated-layout-signoff-corpus-production-gate"
        self.minimumCaseCount = try container.decodeIfPresent(Int.self, forKey: .minimumCaseCount) ?? 1
        self.requiredCoverageTags = try container.decodeIfPresent(
            [String].self,
            forKey: .requiredCoverageTags
        ) ?? []
        self.requiredStageFamilies = try container.decodeIfPresent(
            [XcircuiteGeneratedLayoutSignoffStageFamily].self,
            forKey: .requiredStageFamilies
        ) ?? [.layout, .drc, .lvs, .pex]
        self.requiredOracleReadinessFamilies = try container.decodeIfPresent(
            [XcircuiteGeneratedLayoutSignoffStageFamily].self,
            forKey: .requiredOracleReadinessFamilies
        ) ?? [.drc, .lvs, .pex]
        self.acceptedOracleReadinessStatuses = try container.decodeIfPresent(
            [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus].self,
            forKey: .acceptedOracleReadinessStatuses
        ) ?? [.ready]
        self.requireReportPassed = try container.decodeIfPresent(Bool.self, forKey: .requireReportPassed) ?? true
        self.requireArtifactHashes = try container.decodeIfPresent(Bool.self, forKey: .requireArtifactHashes) ?? true
        self.requireArtifactByteCounts = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireArtifactByteCounts
        ) ?? true
        self.requireArtifactIntegrityPassed = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireArtifactIntegrityPassed
        ) ?? true
        self.requireReadyOracleEvidenceRefs = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireReadyOracleEvidenceRefs
        ) ?? true
        self.requireReadyOracleEvidenceHashes = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireReadyOracleEvidenceHashes
        ) ?? true
        self.requireReadyOracleEvidenceByteCounts = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireReadyOracleEvidenceByteCounts
        ) ?? true
        self.allowExpectedVerdictMismatches = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowExpectedVerdictMismatches
        ) ?? false
        self.minimumSourceArtifactCount = try container.decodeIfPresent(
            Int.self,
            forKey: .minimumSourceArtifactCount
        ) ?? 1
        self.minimumSignoffArtifactCount = try container.decodeIfPresent(
            Int.self,
            forKey: .minimumSignoffArtifactCount
        ) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(policyID, forKey: .policyID)
        try container.encode(minimumCaseCount, forKey: .minimumCaseCount)
        try container.encode(requiredCoverageTags, forKey: .requiredCoverageTags)
        try container.encode(requiredStageFamilies, forKey: .requiredStageFamilies)
        try container.encode(requiredOracleReadinessFamilies, forKey: .requiredOracleReadinessFamilies)
        try container.encode(acceptedOracleReadinessStatuses, forKey: .acceptedOracleReadinessStatuses)
        try container.encode(requireReportPassed, forKey: .requireReportPassed)
        try container.encode(requireArtifactHashes, forKey: .requireArtifactHashes)
        try container.encode(requireArtifactByteCounts, forKey: .requireArtifactByteCounts)
        try container.encode(requireArtifactIntegrityPassed, forKey: .requireArtifactIntegrityPassed)
        try container.encode(requireReadyOracleEvidenceRefs, forKey: .requireReadyOracleEvidenceRefs)
        try container.encode(requireReadyOracleEvidenceHashes, forKey: .requireReadyOracleEvidenceHashes)
        try container.encode(requireReadyOracleEvidenceByteCounts, forKey: .requireReadyOracleEvidenceByteCounts)
        try container.encode(allowExpectedVerdictMismatches, forKey: .allowExpectedVerdictMismatches)
        try container.encode(minimumSourceArtifactCount, forKey: .minimumSourceArtifactCount)
        try container.encode(minimumSignoffArtifactCount, forKey: .minimumSignoffArtifactCount)
    }
}
