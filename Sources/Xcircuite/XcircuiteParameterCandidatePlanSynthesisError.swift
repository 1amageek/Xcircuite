import Foundation
import DesignFlowKernel

public enum XcircuiteParameterCandidatePlanSynthesisError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case missingParameterCandidatesReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: FlowArtifactVerificationStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String?)
    case runMismatch(expected: String, actual: String)
    case problemMismatch(expected: String, actual: String)
    case candidateNotFound(candidateID: String?, rank: Int?)
    case candidateRejectedByFeedback(candidateID: String, statuses: [String], failedGateIDs: [String])
    case noEligibleCandidateAfterFeedback(excludedCandidateIDs: [String])
    case sourceActionNotFound(actionID: String)
    case invalidRank(Int)
    case invalidFeedbackWeight(termID: String, weight: Double)
    case invalidJSONLine(path: String, line: Int)
    case invalidRejectedPlanJSONLine(path: String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "Parameter candidate plan synthesis requires a planning problem reference."
        case .missingParameterCandidatesReference:
            "Parameter candidate plan synthesis requires a parameter candidates reference."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Parameter candidate plan artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Parameter candidate plan artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Parameter candidate plan artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .runMismatch(let expected, let actual):
            "Parameter candidate run mismatch: expected \(expected), got \(actual)."
        case .problemMismatch(let expected, let actual):
            "Parameter candidate problem mismatch: expected \(expected), got \(actual)."
        case .candidateNotFound(let candidateID, let rank):
            "No parameter candidate matched candidateID=\(candidateID ?? "<nil>") rank=\(rank.map(String.init) ?? "<nil>")."
        case .candidateRejectedByFeedback(let candidateID, let statuses, let failedGateIDs):
            "Parameter candidate \(candidateID) is excluded by rejected-plan feedback statuses=\(statuses.joined(separator: ",")) failedGateIDs=\(failedGateIDs.joined(separator: ","))."
        case .noEligibleCandidateAfterFeedback(let excludedCandidateIDs):
            "No eligible parameter candidate remains after rejected-plan feedback excluded \(excludedCandidateIDs.joined(separator: ","))."
        case .sourceActionNotFound(let actionID):
            "No planning candidate action matched parameter candidate source action \(actionID)."
        case .invalidRank(let value):
            "Parameter candidate rank must be greater than zero, got \(value)."
        case .invalidFeedbackWeight(let termID, let weight):
            "Feedback weighting term \(termID) must be finite and non-negative, got \(weight)."
        case .invalidJSONLine(let path, let line):
            "Parameter candidates file \(path) contains invalid JSON at line \(line)."
        case .invalidRejectedPlanJSONLine(let path, let line):
            "Rejected plans file \(path) contains invalid JSON at line \(line)."
        }
    }
}
