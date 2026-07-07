import Foundation

public enum XcircuiteVerifiedImprovementCorpusError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyCorpus
    case duplicateCaseID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Verified improvement corpus schema version \(version) is not supported."
        case .emptyCorpus:
            return "Verified improvement corpus suite must include at least one case."
        case .duplicateCaseID(let caseID):
            return "Verified improvement corpus suite contains duplicate case ID \(caseID)."
        }
    }
}
