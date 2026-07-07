import Foundation

public enum XcircuiteRejectedFeedbackLearningReportValidationError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case invalidIdentifier(field: String, value: String)
    case invalidProjectRelativePath(field: String, path: String)
    case negativeCount(field: String, value: Int)
    case invalidRank(field: String, candidateID: String, value: Int)
    case nonFiniteValue(field: String, candidateID: String, value: Double)
    case negativeValue(field: String, candidateID: String, value: Double)
    case countMismatch(field: String, expected: Int, actual: Int)
    case rankDeltaMismatch(candidateID: String, expected: Int, actual: Int)
    case duplicateIdentifier(field: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Rejected feedback learning report schema version \(version) is not supported."
        case .emptyField(let field):
            return "Rejected feedback learning report field \(field) must not be empty."
        case .invalidIdentifier(let field, let value):
            return "Rejected feedback learning report field \(field) contains an invalid identifier: \(value)."
        case .invalidProjectRelativePath(let field, let path):
            return "Rejected feedback learning report field \(field) contains an unsafe project-relative path: \(path)."
        case .negativeCount(let field, let value):
            return "Rejected feedback learning report field \(field) must not be negative: \(value)."
        case .invalidRank(let field, let candidateID, let value):
            return "Rejected feedback learning report candidate \(candidateID) has invalid \(field): \(value)."
        case .nonFiniteValue(let field, let candidateID, let value):
            return "Rejected feedback learning report candidate \(candidateID) has non-finite \(field): \(value)."
        case .negativeValue(let field, let candidateID, let value):
            return "Rejected feedback learning report candidate \(candidateID) has negative \(field): \(value)."
        case .countMismatch(let field, let expected, let actual):
            return "Rejected feedback learning report count \(field) is \(actual), expected \(expected)."
        case .rankDeltaMismatch(let candidateID, let expected, let actual):
            return "Rejected feedback learning report candidate \(candidateID) has rankDelta \(actual), expected \(expected)."
        case .duplicateIdentifier(let field, let value):
            return "Rejected feedback learning report field \(field) contains a duplicate identifier: \(value)."
        }
    }
}
