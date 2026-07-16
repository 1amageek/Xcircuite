import Foundation
import DesignFlowKernel

public enum XcircuiteParameterCandidateGenerationError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: FlowArtifactVerificationStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String?)
    case runMismatch(expected: String, actual: String)
    case invalidMaxCandidates(Int)
    case invalidPreviousParameterCandidateJSONLine(path: String, line: Int)
    case invalidRejectedPlanJSONLine(path: String, line: Int)
    case invalidParetoCandidateJSONLine(path: String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "Parameter candidate generation requires a planning problem reference."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Parameter candidate artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Parameter candidate artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Parameter candidate artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .runMismatch(let expected, let actual):
            "Planning problem run mismatch: expected \(expected), got \(actual)."
        case .invalidMaxCandidates(let value):
            "maxCandidates must be greater than zero, got \(value)."
        case .invalidPreviousParameterCandidateJSONLine(let path, let line):
            "Previous parameter candidate artifact \(path) contains invalid JSON at line \(line)."
        case .invalidRejectedPlanJSONLine(let path, let line):
            "Rejected plan artifact \(path) contains invalid JSON at line \(line)."
        case .invalidParetoCandidateJSONLine(let path, let line):
            "Pareto candidate artifact \(path) contains invalid JSON at line \(line)."
        }
    }
}
