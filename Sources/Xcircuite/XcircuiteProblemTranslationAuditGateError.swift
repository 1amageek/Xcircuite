import Foundation

public enum XcircuiteProblemTranslationAuditGateError: Error, LocalizedError, Equatable {
    case blocking(runID: String, problemID: String, diagnosticCodes: [String])

    public var errorDescription: String? {
        switch self {
        case .blocking(let runID, let problemID, let diagnosticCodes):
            let codes = diagnosticCodes.isEmpty ? "none" : diagnosticCodes.joined(separator: ",")
            return "Problem translation audit blocks planner entry for run \(runID), problem \(problemID). Diagnostic codes: \(codes)."
        }
    }
}
