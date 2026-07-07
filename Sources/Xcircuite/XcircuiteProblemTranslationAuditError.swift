import Foundation
import XcircuitePackage

public enum XcircuiteProblemTranslationAuditError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String?)
    case runMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "No planning problem artifact ID or path was provided."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain planning problem artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Planning problem artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Planning problem artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Planning problem artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .runMismatch(let expected, let actual):
            "Planning problem runID \(actual) does not match requested runID \(expected)."
        }
    }
}
