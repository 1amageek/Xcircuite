import Foundation

public enum XcircuiteGeneratedLayoutFailureLadderCoverageAuditError: Error, Equatable, Sendable {
    case unsupportedPolicySchemaVersion(Int)
    case unsupportedReportSchemaVersion(Int)
    case emptyReportSet
    case invalidMinimumReportCount(Int)
}
