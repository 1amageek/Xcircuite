import Foundation

public struct XcircuiteRetainedSignoffReport: Codable, Sendable, Hashable {
    private static let supportedReadinessDomains: Set<String> = ["drc", "lvs", "pex"]

    public var schemaVersion: Int
    public var kind: String
    public var suiteID: String
    public var status: String
    public var summary: Summary
    public var externalOracleResults: [ExternalOracleResult]
    public var failures: [Failure]

    public init(
        schemaVersion: Int,
        kind: String,
        suiteID: String,
        status: String,
        summary: Summary,
        externalOracleResults: [ExternalOracleResult],
        failures: [Failure]
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.externalOracleResults = externalOracleResults
        self.failures = failures
    }

    public var provesRetainedExternalOracleInfrastructureReadiness: Bool {
        schemaVersion == 1
            && kind == "retained-signoff-report"
            && status == "passed"
            && summary.externalOracleQualificationStatus == "passed"
            && failures.isEmpty
            && !externalOracleResults.isEmpty
            && externalOracleResults.allSatisfy(\.provesRetainedExternalOracleReadiness)
    }

    public var passingExternalOracleResults: [ExternalOracleResult] {
        externalOracleResults.filter(\.provesRetainedExternalOracleReadiness)
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var dashboardStatus: String?
        public var externalOracleStatus: String?
        public var externalOracleQualificationStatus: String?
        public var externalOracleLaneCount: Int?
        public var passedExternalOracleLaneCount: Int?
        public var blockedExternalOracleLaneCount: Int?
        public var failedExternalOracleLaneCount: Int?

        public init(
            dashboardStatus: String? = nil,
            externalOracleStatus: String? = nil,
            externalOracleQualificationStatus: String? = nil,
            externalOracleLaneCount: Int? = nil,
            passedExternalOracleLaneCount: Int? = nil,
            blockedExternalOracleLaneCount: Int? = nil,
            failedExternalOracleLaneCount: Int? = nil
        ) {
            self.dashboardStatus = dashboardStatus
            self.externalOracleStatus = externalOracleStatus
            self.externalOracleQualificationStatus = externalOracleQualificationStatus
            self.externalOracleLaneCount = externalOracleLaneCount
            self.passedExternalOracleLaneCount = passedExternalOracleLaneCount
            self.blockedExternalOracleLaneCount = blockedExternalOracleLaneCount
            self.failedExternalOracleLaneCount = failedExternalOracleLaneCount
        }
    }

    public struct ExternalOracleResult: Codable, Sendable, Hashable {
        public var domain: String
        public var status: String
        public var oracleBackendID: String?
        public var qualified: Bool?
        public var caseCount: Int?
        public var passedCaseCount: Int?
        public var failedCaseCount: Int?
        public var passRate: Double?
        public var oracleAgreementRate: Double?
        public var readinessFailureCount: Int?
        public var requiredProbeIDs: [String]?
        public var report: Artifact?

        public init(
            domain: String,
            status: String,
            oracleBackendID: String? = nil,
            qualified: Bool? = nil,
            caseCount: Int? = nil,
            passedCaseCount: Int? = nil,
            failedCaseCount: Int? = nil,
            passRate: Double? = nil,
            oracleAgreementRate: Double? = nil,
            readinessFailureCount: Int? = nil,
            requiredProbeIDs: [String]? = nil,
            report: Artifact? = nil
        ) {
            self.domain = domain
            self.status = status
            self.oracleBackendID = oracleBackendID
            self.qualified = qualified
            self.caseCount = caseCount
            self.passedCaseCount = passedCaseCount
            self.failedCaseCount = failedCaseCount
            self.passRate = passRate
            self.oracleAgreementRate = oracleAgreementRate
            self.readinessFailureCount = readinessFailureCount
            self.requiredProbeIDs = requiredProbeIDs
            self.report = report
        }

        public var provesRetainedExternalOracleReadiness: Bool {
            status == "passed"
                && XcircuiteRetainedSignoffReport.supportedReadinessDomains.contains(domain)
                && qualified == true
                && readinessFailureCount == 0
                && hasPositiveCaseCoverage
                && hasPassingCaseCounts
                && hasPassingRates
                && report?.provesRetainedExternalOracleReportEvidence == true
        }

        private var hasPositiveCaseCoverage: Bool {
            guard let caseCount else {
                return false
            }
            return caseCount > 0
        }

        private var hasPassingCaseCounts: Bool {
            guard let caseCount, let passedCaseCount, let failedCaseCount else {
                return false
            }
            return passedCaseCount == caseCount && failedCaseCount == 0
        }

        private var hasPassingRates: Bool {
            guard let passRate, passRate.isFinite, passRate >= 1 else {
                return false
            }
            if let oracleAgreementRate {
                return oracleAgreementRate.isFinite && oracleAgreementRate >= 1
            }
            return true
        }
    }

    public struct Artifact: Codable, Sendable, Hashable {
        private static let hexDigits = Set("0123456789abcdefABCDEF")

        public var status: String?
        public var path: String?
        public var sha256: String?
        public var byteCount: Int64?

        public init(
            status: String? = nil,
            path: String? = nil,
            sha256: String? = nil,
            byteCount: Int64? = nil
        ) {
            self.status = status
            self.path = path
            self.sha256 = sha256
            self.byteCount = byteCount
        }

        public var provesRetainedExternalOracleReportEvidence: Bool {
            guard status == "available",
                  let path,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let sha256,
                  Self.isSHA256(sha256),
                  let byteCount,
                  byteCount > 0 else {
                return false
            }
            return true
        }

        private static func isSHA256(_ value: String) -> Bool {
            value.count == 64 && value.allSatisfy { hexDigits.contains($0) }
        }
    }

    public struct Failure: Codable, Sendable, Hashable {
        public var code: String?
        public var message: String?
        public var reason: String?

        public init(code: String? = nil, message: String? = nil, reason: String? = nil) {
            self.code = code
            self.message = message
            self.reason = reason
        }
    }
}
