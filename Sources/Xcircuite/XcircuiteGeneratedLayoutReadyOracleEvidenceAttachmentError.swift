import Foundation

public enum XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentError: Error, Equatable, Sendable {
    case unsupportedReportSchemaVersion(Int)
    case unsupportedRetainedSignoffReportSchemaVersion(Int)
    case invalidRetainedSignoffReportKind(String)
    case noRetainedExternalOracleLanes
}
