import Foundation

public enum XcircuiteGeneratedLayoutSignoffCorpusValidationError: Error, LocalizedError, Equatable {
    case unsupportedReportSchemaVersion(Int)
    case unsupportedPolicySchemaVersion(Int)
    case invalidMinimumCaseCount(Int)
    case invalidMinimumSourceArtifactCount(Int)
    case invalidMinimumSignoffArtifactCount(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedReportSchemaVersion(let version):
            return "Generated layout signoff corpus report schema version \(version) is not supported."
        case .unsupportedPolicySchemaVersion(let version):
            return "Generated layout signoff corpus validation policy schema version \(version) is not supported."
        case .invalidMinimumCaseCount(let count):
            return "Generated layout signoff corpus validation minimum case count \(count) is invalid."
        case .invalidMinimumSourceArtifactCount(let count):
            return "Generated layout signoff corpus validation minimum source artifact count \(count) is invalid."
        case .invalidMinimumSignoffArtifactCount(let count):
            return "Generated layout signoff corpus validation minimum signoff artifact count \(count) is invalid."
        }
    }
}
