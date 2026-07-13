import Foundation
import DesignFlowKernel

public enum XcircuiteCandidatePlanVerificationError: Error, LocalizedError, Equatable {
    case missingCandidatePlanReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String?)
    case runMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingCandidatePlanReference:
            "Candidate plan verification requires a candidate plan artifact ID or path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Candidate plan verification artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Candidate plan verification artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Candidate plan verification artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .runMismatch(let expected, let actual):
            "Candidate plan verification run mismatch: expected \(expected), got \(actual)."
        }
    }
}
