import Foundation
import XcircuitePackage

public struct XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var policyID: String
    public var status: Status
    public var summary: Summary
    public var missingRequirements: [MissingRequirement]
    public var suggestedActions: [SuggestedAction]
    public var policyArtifact: XcircuiteFileReference?
    public var auditArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        policyID: String,
        status: Status,
        summary: Summary,
        missingRequirements: [MissingRequirement],
        suggestedActions: [SuggestedAction],
        policyArtifact: XcircuiteFileReference? = nil,
        auditArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.policyID = policyID
        self.status = status
        self.summary = summary
        self.missingRequirements = missingRequirements
        self.suggestedActions = suggestedActions
        self.policyArtifact = policyArtifact
        self.auditArtifact = auditArtifact
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case satisfied
        case incomplete
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var caseCount: Int
        public var reportedCaseCount: Int
        public var uniqueCaseCount: Int
        public var duplicateCaseCount: Int
        public var minimumCaseCount: Int
        public var coveredCoverageTags: [String]
        public var missingCoverageTags: [String]
        public var observedSourceArtifactFormats: [String]
        public var missingSourceArtifactFormats: [String]
        public var observedSignoffArtifactIDs: [String]
        public var missingSignoffArtifactIDs: [String]
        public var observedStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var missingStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var readyOracleEvidenceRefCount: Int
        public var missingRequirementCount: Int

        public init(
            caseCount: Int,
            reportedCaseCount: Int? = nil,
            uniqueCaseCount: Int? = nil,
            duplicateCaseCount: Int = 0,
            minimumCaseCount: Int,
            coveredCoverageTags: [String],
            missingCoverageTags: [String],
            observedSourceArtifactFormats: [String],
            missingSourceArtifactFormats: [String],
            observedSignoffArtifactIDs: [String],
            missingSignoffArtifactIDs: [String],
            observedStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            missingStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            readyOracleEvidenceRefCount: Int,
            missingRequirementCount: Int
        ) {
            self.caseCount = caseCount
            self.reportedCaseCount = reportedCaseCount ?? caseCount
            self.uniqueCaseCount = uniqueCaseCount ?? caseCount
            self.duplicateCaseCount = duplicateCaseCount
            self.minimumCaseCount = minimumCaseCount
            self.coveredCoverageTags = coveredCoverageTags
            self.missingCoverageTags = missingCoverageTags
            self.observedSourceArtifactFormats = observedSourceArtifactFormats
            self.missingSourceArtifactFormats = missingSourceArtifactFormats
            self.observedSignoffArtifactIDs = observedSignoffArtifactIDs
            self.missingSignoffArtifactIDs = missingSignoffArtifactIDs
            self.observedStageFamilies = observedStageFamilies
            self.missingStageFamilies = missingStageFamilies
            self.readyOracleEvidenceRefCount = readyOracleEvidenceRefCount
            self.missingRequirementCount = missingRequirementCount
        }

        enum CodingKeys: String, CodingKey {
            case caseCount
            case reportedCaseCount
            case uniqueCaseCount
            case duplicateCaseCount
            case minimumCaseCount
            case coveredCoverageTags
            case missingCoverageTags
            case observedSourceArtifactFormats
            case missingSourceArtifactFormats
            case observedSignoffArtifactIDs
            case missingSignoffArtifactIDs
            case observedStageFamilies
            case missingStageFamilies
            case readyOracleEvidenceRefCount
            case missingRequirementCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let caseCount = try container.decode(Int.self, forKey: .caseCount)
            self.caseCount = caseCount
            self.reportedCaseCount = try container.decodeIfPresent(Int.self, forKey: .reportedCaseCount) ?? caseCount
            self.uniqueCaseCount = try container.decodeIfPresent(Int.self, forKey: .uniqueCaseCount) ?? caseCount
            self.duplicateCaseCount = try container.decodeIfPresent(Int.self, forKey: .duplicateCaseCount) ?? 0
            self.minimumCaseCount = try container.decode(Int.self, forKey: .minimumCaseCount)
            self.coveredCoverageTags = try container.decode([String].self, forKey: .coveredCoverageTags)
            self.missingCoverageTags = try container.decode([String].self, forKey: .missingCoverageTags)
            self.observedSourceArtifactFormats = try container.decode(
                [String].self,
                forKey: .observedSourceArtifactFormats
            )
            self.missingSourceArtifactFormats = try container.decode(
                [String].self,
                forKey: .missingSourceArtifactFormats
            )
            self.observedSignoffArtifactIDs = try container.decode([String].self, forKey: .observedSignoffArtifactIDs)
            self.missingSignoffArtifactIDs = try container.decode([String].self, forKey: .missingSignoffArtifactIDs)
            self.observedStageFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .observedStageFamilies
            )
            self.missingStageFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .missingStageFamilies
            )
            self.readyOracleEvidenceRefCount = try container.decode(Int.self, forKey: .readyOracleEvidenceRefCount)
            self.missingRequirementCount = try container.decode(Int.self, forKey: .missingRequirementCount)
        }
    }

    public struct MissingRequirement: Codable, Sendable, Hashable {
        public var kind: String
        public var identifier: String
        public var message: String

        public init(kind: String, identifier: String, message: String) {
            self.kind = kind
            self.identifier = identifier
            self.message = message
        }
    }

    public struct SuggestedAction: Codable, Sendable, Hashable {
        public var actionKind: String
        public var reason: String
        public var targetIdentifier: String?

        public init(actionKind: String, reason: String, targetIdentifier: String? = nil) {
            self.actionKind = actionKind
            self.reason = reason
            self.targetIdentifier = targetIdentifier
        }
    }
}
