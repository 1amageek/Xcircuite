import Foundation

public enum XcircuiteGeneratedLayoutSignoffPromotionAssessmentError: Error, LocalizedError, Equatable {
    case unsupportedRequestSchemaVersion(Int)
    case unsupportedQualificationSchemaVersion(Int)
    case unsupportedRetainedSignoffReportSchemaVersion(Int)
    case invalidRetainedSignoffReportKind(String)
    case emptyRequiredExternalOracleDomains
    case duplicateRequiredExternalOracleDomain(XcircuiteGeneratedLayoutSignoffStageFamily)
    case unsupportedRequiredExternalOracleDomain(XcircuiteGeneratedLayoutSignoffStageFamily)
    case retainedSignoffReportArtifactMissing
    case retainedSignoffReportArtifactWithoutReport
    case invalidRetainedSignoffReportArtifactPath(String)
    case invalidRetainedSignoffReportArtifactSHA256(path: String, sha256: String)
    case invalidRetainedSignoffReportArtifactByteCount(path: String, byteCount: Int64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRequestSchemaVersion(let version):
            return "Generated layout signoff promotion assessment request schema version \(version) is not supported."
        case .unsupportedQualificationSchemaVersion(let version):
            return "Generated layout signoff corpus qualification schema version \(version) is not supported."
        case .unsupportedRetainedSignoffReportSchemaVersion(let version):
            return "Retained signoff report schema version \(version) is not supported."
        case .invalidRetainedSignoffReportKind(let kind):
            return "Retained signoff report kind \(kind) is not supported."
        case .emptyRequiredExternalOracleDomains:
            return "Generated layout signoff promotion assessment requires at least one external oracle domain."
        case .duplicateRequiredExternalOracleDomain(let domain):
            return "Generated layout signoff promotion assessment contains duplicate required external oracle domain \(domain.rawValue)."
        case .unsupportedRequiredExternalOracleDomain(let domain):
            return "Generated layout signoff promotion assessment does not support required external oracle domain \(domain.rawValue)."
        case .retainedSignoffReportArtifactMissing:
            return "Retained signoff report artifact URL is required when retained external oracle suite evidence is provided."
        case .retainedSignoffReportArtifactWithoutReport:
            return "Retained signoff report artifact URL was provided without a retained signoff report."
        case .invalidRetainedSignoffReportArtifactPath(let path):
            return "Retained signoff report artifact path is invalid: \(path)."
        case .invalidRetainedSignoffReportArtifactSHA256(let path, let sha256):
            return "Retained signoff report artifact \(path) has an invalid SHA-256 digest: \(sha256)."
        case .invalidRetainedSignoffReportArtifactByteCount(let path, let byteCount):
            return "Retained signoff report artifact \(path) has an invalid byte count: \(byteCount)."
        }
    }
}
