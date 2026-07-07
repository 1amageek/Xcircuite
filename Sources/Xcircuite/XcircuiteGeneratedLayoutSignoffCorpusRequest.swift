import DesignFlowKernel
import Foundation

public struct XcircuiteGeneratedLayoutSignoffCorpusRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var requiredCoverageTags: [String]
    public var cases: [CaseRequest]

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        requiredCoverageTags: [String],
        cases: [CaseRequest]
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.requiredCoverageTags = requiredCoverageTags
        self.cases = cases
    }

    public struct CaseRequest: Codable, Sendable, Hashable {
        public var caseID: String
        public var runID: String
        public var expectedRunStatus: FlowRunStatus
        public var expectedStages: [ExpectedStage]
        public var coverageTags: [String]
        public var oracleReadiness: [OracleReadiness]

        public init(
            caseID: String,
            runID: String,
            expectedRunStatus: FlowRunStatus = .succeeded,
            expectedStages: [ExpectedStage],
            coverageTags: [String],
            oracleReadiness: [OracleReadiness]
        ) {
            self.caseID = caseID
            self.runID = runID
            self.expectedRunStatus = expectedRunStatus
            self.expectedStages = expectedStages
            self.coverageTags = coverageTags
            self.oracleReadiness = oracleReadiness
        }
    }

    public struct ExpectedStage: Codable, Sendable, Hashable {
        public var stageID: String
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily
        public var expectedStatus: FlowStageStatus

        public init(
            stageID: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily,
            expectedStatus: FlowStageStatus = .succeeded
        ) {
            self.stageID = stageID
            self.family = family
            self.expectedStatus = expectedStatus
        }
    }

    public struct OracleReadiness: Codable, Sendable, Hashable {
        public var domain: XcircuiteGeneratedLayoutSignoffStageFamily
        public var backendID: String
        public var status: OracleReadinessStatus
        public var reason: String
        public var evidenceRefs: [OracleEvidenceReference]

        public init(
            domain: XcircuiteGeneratedLayoutSignoffStageFamily,
            backendID: String,
            status: OracleReadinessStatus,
            reason: String,
            evidenceRefs: [OracleEvidenceReference] = []
        ) {
            self.domain = domain
            self.backendID = backendID
            self.status = status
            self.reason = reason
            self.evidenceRefs = evidenceRefs
        }

        private enum CodingKeys: String, CodingKey {
            case domain
            case backendID
            case status
            case reason
            case evidenceRefs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.domain = try container.decode(XcircuiteGeneratedLayoutSignoffStageFamily.self, forKey: .domain)
            self.backendID = try container.decode(String.self, forKey: .backendID)
            self.status = try container.decode(OracleReadinessStatus.self, forKey: .status)
            self.reason = try container.decode(String.self, forKey: .reason)
            self.evidenceRefs = try container.decodeIfPresent(
                [OracleEvidenceReference].self,
                forKey: .evidenceRefs
            ) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(domain, forKey: .domain)
            try container.encode(backendID, forKey: .backendID)
            try container.encode(status, forKey: .status)
            try container.encode(reason, forKey: .reason)
            try container.encode(evidenceRefs, forKey: .evidenceRefs)
        }
    }

    public struct OracleEvidenceReference: Codable, Sendable, Hashable {
        public var role: String
        public var path: String
        public var kind: String
        public var format: String
        public var sha256: String?
        public var byteCount: Int64?

        public init(
            role: String,
            path: String,
            kind: String,
            format: String,
            sha256: String? = nil,
            byteCount: Int64? = nil
        ) {
            self.role = role
            self.path = path
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
        }
    }

    public enum OracleReadinessStatus: String, Codable, Sendable, Hashable {
        case ready
        case blocked
        case notConfigured = "not-configured"
    }
}
