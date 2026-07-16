import DesignFlowKernel
import Foundation
import DesignFlowKernel

public enum XcircuiteGeneratedLayoutSignoffCorpusReportValidationError: Error, Equatable, LocalizedError {
    case invalidIntegrityStatus(path: String, status: String)
    case missingVerifiedSHA256(path: String)
    case invalidVerifiedSHA256(path: String, sha256: String)
    case missingVerifiedByteCount(path: String)
    case invalidByteCount(path: String, byteCount: Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidIntegrityStatus(let path, let status):
            "Generated layout signoff corpus artifact \(path) has an unknown integrity status: \(status)."
        case .missingVerifiedSHA256(let path):
            "Generated layout signoff corpus artifact \(path) is verified but does not include a SHA-256 digest."
        case .invalidVerifiedSHA256(let path, let sha256):
            "Generated layout signoff corpus artifact \(path) is verified but has an invalid SHA-256 digest: \(sha256)."
        case .missingVerifiedByteCount(let path):
            "Generated layout signoff corpus artifact \(path) is verified but does not include a byte count."
        case .invalidByteCount(let path, let byteCount):
            "Generated layout signoff corpus artifact \(path) has an invalid byte count: \(byteCount)."
        }
    }
}

public struct XcircuiteGeneratedLayoutSignoffCorpusReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var status: Status
    public var summary: Summary
    public var caseResults: [CaseResult]
    public var suiteSpecArtifact: ArtifactReference?
    public var reportArtifact: ArtifactReference?

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        status: Status,
        summary: Summary,
        caseResults: [CaseResult],
        suiteSpecArtifact: ArtifactReference? = nil,
        reportArtifact: ArtifactReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.caseResults = caseResults
        self.suiteSpecArtifact = suiteSpecArtifact
        self.reportArtifact = reportArtifact
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case passed
        case failed
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var caseCount: Int
        public var passedCaseCount: Int
        public var failedCaseCount: Int
        public var requiredCoverageTags: [String]
        public var coveredCoverageTags: [String]
        public var missingCoverageTags: [String]
        public var stageFamilyCounts: [String: Int]
        public var expectedVerdictMismatchCount: Int
        public var oracleReadinessDeclaredCaseCount: Int
        public var standardLayoutArtifactCount: Int
        public var signoffArtifactCount: Int

        public init(
            caseCount: Int,
            passedCaseCount: Int,
            failedCaseCount: Int,
            requiredCoverageTags: [String],
            coveredCoverageTags: [String],
            missingCoverageTags: [String],
            stageFamilyCounts: [String: Int],
            expectedVerdictMismatchCount: Int,
            oracleReadinessDeclaredCaseCount: Int,
            standardLayoutArtifactCount: Int,
            signoffArtifactCount: Int
        ) {
            self.caseCount = caseCount
            self.passedCaseCount = passedCaseCount
            self.failedCaseCount = failedCaseCount
            self.requiredCoverageTags = requiredCoverageTags
            self.coveredCoverageTags = coveredCoverageTags
            self.missingCoverageTags = missingCoverageTags
            self.stageFamilyCounts = stageFamilyCounts
            self.expectedVerdictMismatchCount = expectedVerdictMismatchCount
            self.oracleReadinessDeclaredCaseCount = oracleReadinessDeclaredCaseCount
            self.standardLayoutArtifactCount = standardLayoutArtifactCount
            self.signoffArtifactCount = signoffArtifactCount
        }
    }

    public struct CaseResult: Codable, Sendable, Hashable {
        public var caseID: String
        public var runID: String
        public var status: Status
        public var runStatus: FlowRunStatus
        public var expectedRunStatus: FlowRunStatus
        public var runStatusMatches: Bool
        public var coverageTags: [String]
        public var oracleReadiness: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness]
        public var stageResults: [StageResult]
        public var sourceArtifactRefs: [ArtifactReference]
        public var signoffArtifactRefs: [ArtifactReference]
        public var diagnostics: [Diagnostic]

        public init(
            caseID: String,
            runID: String,
            status: Status,
            runStatus: FlowRunStatus,
            expectedRunStatus: FlowRunStatus,
            runStatusMatches: Bool,
            coverageTags: [String],
            oracleReadiness: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness],
            stageResults: [StageResult],
            sourceArtifactRefs: [ArtifactReference],
            signoffArtifactRefs: [ArtifactReference],
            diagnostics: [Diagnostic]
        ) {
            self.caseID = caseID
            self.runID = runID
            self.status = status
            self.runStatus = runStatus
            self.expectedRunStatus = expectedRunStatus
            self.runStatusMatches = runStatusMatches
            self.coverageTags = coverageTags
            self.oracleReadiness = oracleReadiness
            self.stageResults = stageResults
            self.sourceArtifactRefs = sourceArtifactRefs
            self.signoffArtifactRefs = signoffArtifactRefs
            self.diagnostics = diagnostics
        }
    }

    public struct StageResult: Codable, Sendable, Hashable {
        public var stageID: String
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily
        public var status: FlowStageStatus
        public var expectedStatus: FlowStageStatus?
        public var statusMatches: Bool
        public var gateResults: [GateResult]
        public var artifactRefs: [ArtifactSnapshot]
        public var diagnostics: [Diagnostic]

        public init(
            stageID: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily,
            status: FlowStageStatus,
            expectedStatus: FlowStageStatus?,
            statusMatches: Bool,
            gateResults: [GateResult],
            artifactRefs: [ArtifactSnapshot],
            diagnostics: [Diagnostic]
        ) {
            self.stageID = stageID
            self.family = family
            self.status = status
            self.expectedStatus = expectedStatus
            self.statusMatches = statusMatches
            self.gateResults = gateResults
            self.artifactRefs = artifactRefs
            self.diagnostics = diagnostics
        }
    }

    public struct GateResult: Codable, Sendable, Hashable {
        public var gateID: String
        public var status: FlowGateStatus
        public var diagnostics: [Diagnostic]

        public init(gateID: String, status: FlowGateStatus, diagnostics: [Diagnostic]) {
            self.gateID = gateID
            self.status = status
            self.diagnostics = diagnostics
        }
    }

    public struct ArtifactSnapshot: Codable, Sendable, Hashable {
        public var role: String
        public var artifactID: String?
        public var stageID: String?
        public var path: String
        public var kind: String
        public var format: String
        public var sha256: String?
        public var byteCount: Int64?
        public var integrityStatus: String?
        public var integrityMessage: String?

        public init(
            role: String,
            artifactID: String?,
            stageID: String?,
            path: String,
            kind: String,
            format: String,
            sha256: String?,
            byteCount: Int64?,
            integrityStatus: String?,
            integrityMessage: String?
        ) throws {
            try Self.validate(
                path: path,
                sha256: sha256,
                byteCount: byteCount,
                integrityStatus: integrityStatus
            )
            self.role = role
            self.artifactID = artifactID
            self.stageID = stageID
            self.path = path
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
            self.integrityStatus = integrityStatus
            self.integrityMessage = integrityMessage
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let role = try container.decode(String.self, forKey: .role)
            let artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
            let stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
            let path = try container.decode(String.self, forKey: .path)
            let kind = try container.decode(String.self, forKey: .kind)
            let format = try container.decode(String.self, forKey: .format)
            let sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            let byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
            let integrityStatus = try container.decodeIfPresent(String.self, forKey: .integrityStatus)
            let integrityMessage = try container.decodeIfPresent(String.self, forKey: .integrityMessage)
            try self.init(
                role: role,
                artifactID: artifactID,
                stageID: stageID,
                path: path,
                kind: kind,
                format: format,
                sha256: sha256,
                byteCount: byteCount,
                integrityStatus: integrityStatus,
                integrityMessage: integrityMessage
            )
        }

        public func encode(to encoder: Encoder) throws {
            try Self.validate(
                path: path,
                sha256: sha256,
                byteCount: byteCount,
                integrityStatus: integrityStatus
            )
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(artifactID, forKey: .artifactID)
            try container.encodeIfPresent(stageID, forKey: .stageID)
            try container.encode(path, forKey: .path)
            try container.encode(kind, forKey: .kind)
            try container.encode(format, forKey: .format)
            try container.encodeIfPresent(sha256, forKey: .sha256)
            try container.encodeIfPresent(byteCount, forKey: .byteCount)
            try container.encodeIfPresent(integrityStatus, forKey: .integrityStatus)
            try container.encodeIfPresent(integrityMessage, forKey: .integrityMessage)
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case artifactID
            case stageID
            case path
            case kind
            case format
            case sha256
            case byteCount
            case integrityStatus
            case integrityMessage
        }

        private static func validate(
            path: String,
            sha256: String?,
            byteCount: Int64?,
            integrityStatus: String?
        ) throws {
            if let byteCount, byteCount <= 0 {
                throw XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.invalidByteCount(
                    path: path,
                    byteCount: byteCount
                )
            }
            guard let integrityStatus else {
                return
            }
            guard let status = FlowRunReviewArtifactIntegrityStatus(rawValue: integrityStatus) else {
                throw XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.invalidIntegrityStatus(
                    path: path,
                    status: integrityStatus
                )
            }
            guard status == .verified else {
                return
            }
            guard let sha256, !sha256.isEmpty else {
                throw XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.missingVerifiedSHA256(path: path)
            }
            guard isValidSHA256(sha256) else {
                throw XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.invalidVerifiedSHA256(
                    path: path,
                    sha256: sha256
                )
            }
            guard byteCount != nil else {
                throw XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.missingVerifiedByteCount(path: path)
            }
        }

        private static func isValidSHA256(_ value: String) -> Bool {
            value.count == 64 && value.allSatisfy { character in
                character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
            }
        }
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public var severity: FlowDiagnosticSeverity
        public var code: String
        public var message: String

        public init(severity: FlowDiagnosticSeverity, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }
}
import CircuiteFoundation
