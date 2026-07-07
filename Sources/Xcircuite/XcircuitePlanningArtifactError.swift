import Foundation

public enum XcircuitePlanningArtifactError: Error, LocalizedError, Equatable {
    case runMismatch(expected: String, actual: String)
    case invalidUTF8
    case invalidJSONLLine(path: String, line: Int, message: String)
    case duplicateRejectedPlan(rejectionID: String)

    public var errorDescription: String? {
        switch self {
        case .runMismatch(let expected, let actual):
            "Planning artifact run mismatch: expected \(expected), got \(actual)."
        case .invalidUTF8:
            "Planning artifact JSONL output was not valid UTF-8."
        case .invalidJSONLLine(let path, let line, let message):
            "Planning artifact JSONL at \(path) has invalid line \(line): \(message)"
        case .duplicateRejectedPlan(let rejectionID):
            "Planning artifact rejected-plan ledger already contains rejectionID \(rejectionID)."
        }
    }
}
