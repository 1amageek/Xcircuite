import Foundation

public enum XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditError: Error, Equatable, Sendable {
    case unsupportedReportSchemaVersion(Int)
    case unsupportedPolicySchemaVersion(Int)
    case invalidMinimumCaseCount(Int)
}
