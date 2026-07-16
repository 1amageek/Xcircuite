import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutSignoffPromotionAssessment: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var promotionID: String
    public var suiteID: String
    public var status: Status
    public var summary: Summary
    public var blockers: [Blocker]
    public var suggestedActions: [SuggestedAction]
    public var qualificationArtifact: ArtifactFingerprint?
    public var retainedSignoffReportArtifact: ArtifactFingerprint?
    public var assessmentArtifact: ArtifactFingerprint?

    public init(
        schemaVersion: Int = 1,
        promotionID: String,
        suiteID: String,
        status: Status,
        summary: Summary,
        blockers: [Blocker],
        suggestedActions: [SuggestedAction],
        qualificationArtifact: ArtifactFingerprint? = nil,
        retainedSignoffReportArtifact: ArtifactFingerprint? = nil,
        assessmentArtifact: ArtifactFingerprint? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.promotionID = promotionID
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.blockers = blockers
        self.suggestedActions = suggestedActions
        self.qualificationArtifact = qualificationArtifact
        self.retainedSignoffReportArtifact = retainedSignoffReportArtifact
        self.assessmentArtifact = assessmentArtifact
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case productionReady = "production-ready"
        case readyForExternalCaseExpansion = "ready-for-external-case-expansion"
        case blocked
    }

    public enum Severity: String, Codable, Sendable, Hashable {
        case error
        case warning
        case info
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var qualificationStatus: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Status
        public var generatedLayoutOracleReady: Bool
        public var externalOracleInfrastructureReady: Bool
        public var retainedSignoffReportStatus: String?
        public var retainedSignoffSuiteID: String?
        public var requiredExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var observedExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var missingExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var externalOracleLaneCount: Int
        public var passedExternalOracleLaneCount: Int
        public var blockedExternalOracleLaneCount: Int
        public var failedExternalOracleLaneCount: Int
        public var generatedLayoutAcceptedOracleStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus]
        public var blockerCount: Int

        public init(
            qualificationStatus: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Status,
            generatedLayoutOracleReady: Bool,
            externalOracleInfrastructureReady: Bool,
            retainedSignoffReportStatus: String?,
            retainedSignoffSuiteID: String?,
            requiredExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily],
            observedExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily],
            missingExternalOracleDomains: [XcircuiteGeneratedLayoutSignoffStageFamily],
            externalOracleLaneCount: Int,
            passedExternalOracleLaneCount: Int,
            blockedExternalOracleLaneCount: Int,
            failedExternalOracleLaneCount: Int,
            generatedLayoutAcceptedOracleStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus],
            blockerCount: Int
        ) {
            self.qualificationStatus = qualificationStatus
            self.generatedLayoutOracleReady = generatedLayoutOracleReady
            self.externalOracleInfrastructureReady = externalOracleInfrastructureReady
            self.retainedSignoffReportStatus = retainedSignoffReportStatus
            self.retainedSignoffSuiteID = retainedSignoffSuiteID
            self.requiredExternalOracleDomains = requiredExternalOracleDomains
            self.observedExternalOracleDomains = observedExternalOracleDomains
            self.missingExternalOracleDomains = missingExternalOracleDomains
            self.externalOracleLaneCount = externalOracleLaneCount
            self.passedExternalOracleLaneCount = passedExternalOracleLaneCount
            self.blockedExternalOracleLaneCount = blockedExternalOracleLaneCount
            self.failedExternalOracleLaneCount = failedExternalOracleLaneCount
            self.generatedLayoutAcceptedOracleStatuses = generatedLayoutAcceptedOracleStatuses
            self.blockerCount = blockerCount
        }
    }

    public struct Blocker: Codable, Sendable, Hashable {
        public var severity: Severity
        public var code: String
        public var message: String
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily?
        public var domain: String?
        public var evidencePath: String?

        public init(
            severity: Severity = .error,
            code: String,
            message: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily? = nil,
            domain: String? = nil,
            evidencePath: String? = nil
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.family = family
            self.domain = domain
            self.evidencePath = evidencePath
        }
    }

    public struct SuggestedAction: Codable, Sendable, Hashable {
        public var actionKind: String
        public var reason: String
        public var targetDomain: XcircuiteGeneratedLayoutSignoffStageFamily?

        public init(
            actionKind: String,
            reason: String,
            targetDomain: XcircuiteGeneratedLayoutSignoffStageFamily? = nil
        ) {
            self.actionKind = actionKind
            self.reason = reason
            self.targetDomain = targetDomain
        }
    }

    public struct ArtifactFingerprint: Codable, Sendable, Hashable {
        public var path: String
        public var sha256: String
        public var byteCount: Int64

        public init(path: String, sha256: String, byteCount: Int64) throws {
            try Self.validate(path: path, sha256: sha256, byteCount: byteCount)
            self.path = path
            self.sha256 = sha256
            self.byteCount = byteCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let path = try container.decode(String.self, forKey: .path)
            let sha256 = try container.decode(String.self, forKey: .sha256)
            let byteCount = try container.decode(Int64.self, forKey: .byteCount)
            try self.init(path: path, sha256: sha256, byteCount: byteCount)
        }

        public func encode(to encoder: Encoder) throws {
            try Self.validate(path: path, sha256: sha256, byteCount: byteCount)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(sha256, forKey: .sha256)
            try container.encode(byteCount, forKey: .byteCount)
        }

        private enum CodingKeys: String, CodingKey {
            case path
            case sha256
            case byteCount
        }

        private static func validate(path: String, sha256: String, byteCount: Int64) throws {
            guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .invalidRetainedSignoffReportArtifactPath(path)
            }
            guard isValidSHA256(sha256) else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .invalidRetainedSignoffReportArtifactSHA256(path: path, sha256: sha256)
            }
            guard byteCount > 0 else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .invalidRetainedSignoffReportArtifactByteCount(path: path, byteCount: byteCount)
            }
        }

        private static func isValidSHA256(_ value: String) -> Bool {
            value.count == 64 && value.allSatisfy { character in
                character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
            }
        }
    }
}
