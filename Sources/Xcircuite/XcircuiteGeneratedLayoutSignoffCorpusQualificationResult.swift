import Foundation
import XcircuitePackage

public struct XcircuiteGeneratedLayoutSignoffCorpusQualificationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var policyID: String
    public var status: Status
    public var summary: Summary
    public var failures: [Failure]
    public var policyArtifact: XcircuiteFileReference?
    public var qualificationArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        policyID: String,
        status: Status,
        summary: Summary,
        failures: [Failure],
        policyArtifact: XcircuiteFileReference? = nil,
        qualificationArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.policyID = policyID
        self.status = status
        self.summary = summary
        self.failures = failures
        self.policyArtifact = policyArtifact
        self.qualificationArtifact = qualificationArtifact
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case qualified
        case failed
    }

    public enum FailureSeverity: String, Codable, Sendable, Hashable {
        case error
        case warning
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var reportStatus: XcircuiteGeneratedLayoutSignoffCorpusReport.Status
        public var caseCount: Int
        public var reportedCaseCount: Int
        public var uniqueCaseCount: Int
        public var duplicateCaseCount: Int
        public var minimumCaseCount: Int
        public var passedCaseCount: Int
        public var failedCaseCount: Int
        public var requiredCoverageTags: [String]
        public var coveredCoverageTags: [String]
        public var missingCoverageTags: [String]
        public var requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var observedStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var missingStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var requiredOracleReadinessFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily]
        public var acceptedOracleReadinessStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus]
        public var acceptedOracleReadinessCaseCount: Int
        public var readyOracleEvidenceRefCount: Int
        public var readyOracleReadinessWithoutEvidenceCount: Int
        public var readyOracleEvidenceWithoutHashCount: Int
        public var readyOracleEvidenceWithoutByteCount: Int
        public var expectedVerdictMismatchCount: Int
        public var sourceArtifactCount: Int
        public var reportedSourceArtifactCount: Int
        public var minimumSourceArtifactCount: Int
        public var signoffArtifactCount: Int
        public var reportedSignoffArtifactCount: Int
        public var minimumSignoffArtifactCount: Int
        public var artifactWithoutHashCount: Int
        public var artifactWithoutByteCount: Int
        public var artifactIntegrityFailureCount: Int
        public var failureCount: Int

        public init(
            reportStatus: XcircuiteGeneratedLayoutSignoffCorpusReport.Status,
            caseCount: Int,
            reportedCaseCount: Int? = nil,
            uniqueCaseCount: Int? = nil,
            duplicateCaseCount: Int = 0,
            minimumCaseCount: Int,
            passedCaseCount: Int,
            failedCaseCount: Int,
            requiredCoverageTags: [String],
            coveredCoverageTags: [String],
            missingCoverageTags: [String],
            requiredStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            observedStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            missingStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            requiredOracleReadinessFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
            acceptedOracleReadinessStatuses: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus],
            acceptedOracleReadinessCaseCount: Int,
            readyOracleEvidenceRefCount: Int,
            readyOracleReadinessWithoutEvidenceCount: Int,
            readyOracleEvidenceWithoutHashCount: Int,
            readyOracleEvidenceWithoutByteCount: Int,
            expectedVerdictMismatchCount: Int,
            sourceArtifactCount: Int,
            reportedSourceArtifactCount: Int? = nil,
            minimumSourceArtifactCount: Int,
            signoffArtifactCount: Int,
            reportedSignoffArtifactCount: Int? = nil,
            minimumSignoffArtifactCount: Int,
            artifactWithoutHashCount: Int,
            artifactWithoutByteCount: Int,
            artifactIntegrityFailureCount: Int,
            failureCount: Int
        ) {
            self.reportStatus = reportStatus
            self.caseCount = caseCount
            self.reportedCaseCount = reportedCaseCount ?? caseCount
            self.uniqueCaseCount = uniqueCaseCount ?? caseCount
            self.duplicateCaseCount = duplicateCaseCount
            self.minimumCaseCount = minimumCaseCount
            self.passedCaseCount = passedCaseCount
            self.failedCaseCount = failedCaseCount
            self.requiredCoverageTags = requiredCoverageTags
            self.coveredCoverageTags = coveredCoverageTags
            self.missingCoverageTags = missingCoverageTags
            self.requiredStageFamilies = requiredStageFamilies
            self.observedStageFamilies = observedStageFamilies
            self.missingStageFamilies = missingStageFamilies
            self.requiredOracleReadinessFamilies = requiredOracleReadinessFamilies
            self.acceptedOracleReadinessStatuses = acceptedOracleReadinessStatuses
            self.acceptedOracleReadinessCaseCount = acceptedOracleReadinessCaseCount
            self.readyOracleEvidenceRefCount = readyOracleEvidenceRefCount
            self.readyOracleReadinessWithoutEvidenceCount = readyOracleReadinessWithoutEvidenceCount
            self.readyOracleEvidenceWithoutHashCount = readyOracleEvidenceWithoutHashCount
            self.readyOracleEvidenceWithoutByteCount = readyOracleEvidenceWithoutByteCount
            self.expectedVerdictMismatchCount = expectedVerdictMismatchCount
            self.sourceArtifactCount = sourceArtifactCount
            self.reportedSourceArtifactCount = reportedSourceArtifactCount ?? sourceArtifactCount
            self.minimumSourceArtifactCount = minimumSourceArtifactCount
            self.signoffArtifactCount = signoffArtifactCount
            self.reportedSignoffArtifactCount = reportedSignoffArtifactCount ?? signoffArtifactCount
            self.minimumSignoffArtifactCount = minimumSignoffArtifactCount
            self.artifactWithoutHashCount = artifactWithoutHashCount
            self.artifactWithoutByteCount = artifactWithoutByteCount
            self.artifactIntegrityFailureCount = artifactIntegrityFailureCount
            self.failureCount = failureCount
        }

        private enum CodingKeys: String, CodingKey {
            case reportStatus
            case caseCount
            case reportedCaseCount
            case uniqueCaseCount
            case duplicateCaseCount
            case minimumCaseCount
            case passedCaseCount
            case failedCaseCount
            case requiredCoverageTags
            case coveredCoverageTags
            case missingCoverageTags
            case requiredStageFamilies
            case observedStageFamilies
            case missingStageFamilies
            case requiredOracleReadinessFamilies
            case acceptedOracleReadinessStatuses
            case acceptedOracleReadinessCaseCount
            case readyOracleEvidenceRefCount
            case readyOracleReadinessWithoutEvidenceCount
            case readyOracleEvidenceWithoutHashCount
            case readyOracleEvidenceWithoutByteCount
            case expectedVerdictMismatchCount
            case sourceArtifactCount
            case reportedSourceArtifactCount
            case minimumSourceArtifactCount
            case signoffArtifactCount
            case reportedSignoffArtifactCount
            case minimumSignoffArtifactCount
            case artifactWithoutHashCount
            case artifactWithoutByteCount
            case artifactIntegrityFailureCount
            case failureCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.reportStatus = try container.decode(
                XcircuiteGeneratedLayoutSignoffCorpusReport.Status.self,
                forKey: .reportStatus
            )
            self.caseCount = try container.decode(Int.self, forKey: .caseCount)
            self.reportedCaseCount = try container.decodeIfPresent(Int.self, forKey: .reportedCaseCount)
                ?? self.caseCount
            self.uniqueCaseCount = try container.decodeIfPresent(Int.self, forKey: .uniqueCaseCount)
                ?? self.caseCount
            self.duplicateCaseCount = try container.decodeIfPresent(Int.self, forKey: .duplicateCaseCount) ?? 0
            self.minimumCaseCount = try container.decode(Int.self, forKey: .minimumCaseCount)
            self.passedCaseCount = try container.decode(Int.self, forKey: .passedCaseCount)
            self.failedCaseCount = try container.decode(Int.self, forKey: .failedCaseCount)
            self.requiredCoverageTags = try container.decode([String].self, forKey: .requiredCoverageTags)
            self.coveredCoverageTags = try container.decode([String].self, forKey: .coveredCoverageTags)
            self.missingCoverageTags = try container.decode([String].self, forKey: .missingCoverageTags)
            self.requiredStageFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .requiredStageFamilies
            )
            self.observedStageFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .observedStageFamilies
            )
            self.missingStageFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .missingStageFamilies
            )
            self.requiredOracleReadinessFamilies = try container.decode(
                [XcircuiteGeneratedLayoutSignoffStageFamily].self,
                forKey: .requiredOracleReadinessFamilies
            )
            self.acceptedOracleReadinessStatuses = try container.decode(
                [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadinessStatus].self,
                forKey: .acceptedOracleReadinessStatuses
            )
            self.acceptedOracleReadinessCaseCount = try container.decode(
                Int.self,
                forKey: .acceptedOracleReadinessCaseCount
            )
            self.readyOracleEvidenceRefCount = try container.decodeIfPresent(
                Int.self,
                forKey: .readyOracleEvidenceRefCount
            ) ?? 0
            self.readyOracleReadinessWithoutEvidenceCount = try container.decodeIfPresent(
                Int.self,
                forKey: .readyOracleReadinessWithoutEvidenceCount
            ) ?? 0
            self.readyOracleEvidenceWithoutHashCount = try container.decodeIfPresent(
                Int.self,
                forKey: .readyOracleEvidenceWithoutHashCount
            ) ?? 0
            self.readyOracleEvidenceWithoutByteCount = try container.decodeIfPresent(
                Int.self,
                forKey: .readyOracleEvidenceWithoutByteCount
            ) ?? 0
            self.expectedVerdictMismatchCount = try container.decode(
                Int.self,
                forKey: .expectedVerdictMismatchCount
            )
            self.sourceArtifactCount = try container.decode(Int.self, forKey: .sourceArtifactCount)
            self.reportedSourceArtifactCount = try container.decodeIfPresent(
                Int.self,
                forKey: .reportedSourceArtifactCount
            ) ?? self.sourceArtifactCount
            self.minimumSourceArtifactCount = try container.decode(
                Int.self,
                forKey: .minimumSourceArtifactCount
            )
            self.signoffArtifactCount = try container.decode(Int.self, forKey: .signoffArtifactCount)
            self.reportedSignoffArtifactCount = try container.decodeIfPresent(
                Int.self,
                forKey: .reportedSignoffArtifactCount
            ) ?? self.signoffArtifactCount
            self.minimumSignoffArtifactCount = try container.decode(
                Int.self,
                forKey: .minimumSignoffArtifactCount
            )
            self.artifactWithoutHashCount = try container.decode(Int.self, forKey: .artifactWithoutHashCount)
            self.artifactWithoutByteCount = try container.decode(Int.self, forKey: .artifactWithoutByteCount)
            self.artifactIntegrityFailureCount = try container.decode(
                Int.self,
                forKey: .artifactIntegrityFailureCount
            )
            self.failureCount = try container.decode(Int.self, forKey: .failureCount)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reportStatus, forKey: .reportStatus)
            try container.encode(caseCount, forKey: .caseCount)
            try container.encode(reportedCaseCount, forKey: .reportedCaseCount)
            try container.encode(uniqueCaseCount, forKey: .uniqueCaseCount)
            try container.encode(duplicateCaseCount, forKey: .duplicateCaseCount)
            try container.encode(minimumCaseCount, forKey: .minimumCaseCount)
            try container.encode(passedCaseCount, forKey: .passedCaseCount)
            try container.encode(failedCaseCount, forKey: .failedCaseCount)
            try container.encode(requiredCoverageTags, forKey: .requiredCoverageTags)
            try container.encode(coveredCoverageTags, forKey: .coveredCoverageTags)
            try container.encode(missingCoverageTags, forKey: .missingCoverageTags)
            try container.encode(requiredStageFamilies, forKey: .requiredStageFamilies)
            try container.encode(observedStageFamilies, forKey: .observedStageFamilies)
            try container.encode(missingStageFamilies, forKey: .missingStageFamilies)
            try container.encode(requiredOracleReadinessFamilies, forKey: .requiredOracleReadinessFamilies)
            try container.encode(acceptedOracleReadinessStatuses, forKey: .acceptedOracleReadinessStatuses)
            try container.encode(acceptedOracleReadinessCaseCount, forKey: .acceptedOracleReadinessCaseCount)
            try container.encode(readyOracleEvidenceRefCount, forKey: .readyOracleEvidenceRefCount)
            try container.encode(
                readyOracleReadinessWithoutEvidenceCount,
                forKey: .readyOracleReadinessWithoutEvidenceCount
            )
            try container.encode(readyOracleEvidenceWithoutHashCount, forKey: .readyOracleEvidenceWithoutHashCount)
            try container.encode(
                readyOracleEvidenceWithoutByteCount,
                forKey: .readyOracleEvidenceWithoutByteCount
            )
            try container.encode(expectedVerdictMismatchCount, forKey: .expectedVerdictMismatchCount)
            try container.encode(sourceArtifactCount, forKey: .sourceArtifactCount)
            try container.encode(reportedSourceArtifactCount, forKey: .reportedSourceArtifactCount)
            try container.encode(minimumSourceArtifactCount, forKey: .minimumSourceArtifactCount)
            try container.encode(signoffArtifactCount, forKey: .signoffArtifactCount)
            try container.encode(reportedSignoffArtifactCount, forKey: .reportedSignoffArtifactCount)
            try container.encode(minimumSignoffArtifactCount, forKey: .minimumSignoffArtifactCount)
            try container.encode(artifactWithoutHashCount, forKey: .artifactWithoutHashCount)
            try container.encode(artifactWithoutByteCount, forKey: .artifactWithoutByteCount)
            try container.encode(artifactIntegrityFailureCount, forKey: .artifactIntegrityFailureCount)
            try container.encode(failureCount, forKey: .failureCount)
        }
    }

    public struct Failure: Codable, Sendable, Hashable {
        public var severity: FailureSeverity
        public var code: String
        public var message: String
        public var caseID: String?
        public var stageID: String?
        public var artifactID: String?
        public var path: String?
        public var coverageTag: String?
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily?

        public init(
            severity: FailureSeverity = .error,
            code: String,
            message: String,
            caseID: String? = nil,
            stageID: String? = nil,
            artifactID: String? = nil,
            path: String? = nil,
            coverageTag: String? = nil,
            family: XcircuiteGeneratedLayoutSignoffStageFamily? = nil
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.caseID = caseID
            self.stageID = stageID
            self.artifactID = artifactID
            self.path = path
            self.coverageTag = coverageTag
            self.family = family
        }
    }
}
