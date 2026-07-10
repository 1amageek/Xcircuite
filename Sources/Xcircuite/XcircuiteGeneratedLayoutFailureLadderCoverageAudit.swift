import Foundation
import XcircuitePackage

public struct XcircuiteGeneratedLayoutFailureLadderCoverageAudit: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var auditID: String
    public var status: Status
    public var summary: Summary
    public var reportCases: [ReportCase]
    public var missingRequirements: [MissingRequirement]
    public var suggestedActions: [SuggestedAction]
    public var policyArtifact: XcircuiteFileReference?
    public var auditArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        auditID: String,
        status: Status,
        summary: Summary,
        reportCases: [ReportCase],
        missingRequirements: [MissingRequirement],
        suggestedActions: [SuggestedAction],
        policyArtifact: XcircuiteFileReference? = nil,
        auditArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.auditID = auditID
        self.status = status
        self.summary = summary
        self.reportCases = reportCases
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
        public var reportCount: Int
        public var uniqueReportCount: Int
        public var duplicateReportCount: Int
        public var minimumReportCount: Int
        public var observedFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var missingFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var observedSuggestedActionKinds: [String]
        public var missingSuggestedActionKinds: [String]
        public var observedEvidenceArtifactIDs: [String]
        public var missingEvidenceArtifactIDs: [String]
        public var reportArtifactRefCount: Int
        public var diagnosticCodeCount: Int
        public var missingRequirementCount: Int

        public init(
            reportCount: Int,
            uniqueReportCount: Int? = nil,
            duplicateReportCount: Int = 0,
            minimumReportCount: Int,
            observedFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            missingFirstFailingFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            observedSuggestedActionKinds: [String],
            missingSuggestedActionKinds: [String],
            observedEvidenceArtifactIDs: [String],
            missingEvidenceArtifactIDs: [String],
            reportArtifactRefCount: Int,
            diagnosticCodeCount: Int,
            missingRequirementCount: Int
        ) {
            self.reportCount = reportCount
            self.uniqueReportCount = uniqueReportCount ?? reportCount
            self.duplicateReportCount = duplicateReportCount
            self.minimumReportCount = minimumReportCount
            self.observedFirstFailingFamilies = observedFirstFailingFamilies
            self.missingFirstFailingFamilies = missingFirstFailingFamilies
            self.observedSuggestedActionKinds = observedSuggestedActionKinds
            self.missingSuggestedActionKinds = missingSuggestedActionKinds
            self.observedEvidenceArtifactIDs = observedEvidenceArtifactIDs
            self.missingEvidenceArtifactIDs = missingEvidenceArtifactIDs
            self.reportArtifactRefCount = reportArtifactRefCount
            self.diagnosticCodeCount = diagnosticCodeCount
            self.missingRequirementCount = missingRequirementCount
        }

        enum CodingKeys: String, CodingKey {
            case reportCount
            case uniqueReportCount
            case duplicateReportCount
            case minimumReportCount
            case observedFirstFailingFamilies
            case missingFirstFailingFamilies
            case observedSuggestedActionKinds
            case missingSuggestedActionKinds
            case observedEvidenceArtifactIDs
            case missingEvidenceArtifactIDs
            case reportArtifactRefCount
            case diagnosticCodeCount
            case missingRequirementCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let reportCount = try container.decode(Int.self, forKey: .reportCount)
            self.reportCount = reportCount
            self.uniqueReportCount = try container.decode(Int.self, forKey: .uniqueReportCount)
            self.duplicateReportCount = try container.decode(Int.self, forKey: .duplicateReportCount)
            self.minimumReportCount = try container.decode(Int.self, forKey: .minimumReportCount)
            self.observedFirstFailingFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .observedFirstFailingFamilies
            )
            self.missingFirstFailingFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .missingFirstFailingFamilies
            )
            self.observedSuggestedActionKinds = try container.decode(
                [String].self,
                forKey: .observedSuggestedActionKinds
            )
            self.missingSuggestedActionKinds = try container.decode(
                [String].self,
                forKey: .missingSuggestedActionKinds
            )
            self.observedEvidenceArtifactIDs = try container.decode(
                [String].self,
                forKey: .observedEvidenceArtifactIDs
            )
            self.missingEvidenceArtifactIDs = try container.decode(
                [String].self,
                forKey: .missingEvidenceArtifactIDs
            )
            self.reportArtifactRefCount = try container.decode(Int.self, forKey: .reportArtifactRefCount)
            self.diagnosticCodeCount = try container.decode(Int.self, forKey: .diagnosticCodeCount)
            self.missingRequirementCount = try container.decode(Int.self, forKey: .missingRequirementCount)
        }
    }

    public struct ReportCase: Codable, Sendable, Hashable {
        public var ladderID: String
        public var runID: String
        public var firstFailingStageID: String?
        public var firstFailingGateID: String?
        public var firstFailingFamily: XcircuiteGeneratedLayoutSignoffStageFamily?
        public var suggestedActionKinds: [String]
        public var evidenceArtifactIDs: [String]
        public var diagnosticCodes: [String]
        public var reportArtifactPath: String?

        public init(
            ladderID: String,
            runID: String,
            firstFailingStageID: String?,
            firstFailingGateID: String?,
            firstFailingFamily: XcircuiteGeneratedLayoutSignoffStageFamily?,
            suggestedActionKinds: [String],
            evidenceArtifactIDs: [String],
            diagnosticCodes: [String],
            reportArtifactPath: String?
        ) {
            self.ladderID = ladderID
            self.runID = runID
            self.firstFailingStageID = firstFailingStageID
            self.firstFailingGateID = firstFailingGateID
            self.firstFailingFamily = firstFailingFamily
            self.suggestedActionKinds = suggestedActionKinds
            self.evidenceArtifactIDs = evidenceArtifactIDs
            self.diagnosticCodes = diagnosticCodes
            self.reportArtifactPath = reportArtifactPath
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
