import Foundation
import XcircuitePackage

public enum XcircuitePlanningProblemGenerationError: Error, LocalizedError, Equatable {
    case missingSummaryReference
    case artifactNotFound(runID: String, artifactID: String)
    case duplicateArtifactReference(runID: String, artifactID: String, count: Int)
    case artifactIntegrityFailed(
        artifactID: String?,
        path: String,
        status: XcircuiteFileReferenceIntegrityStatus,
        message: String
    )
    case explicitPathNotFound(path: String)
    case unsupportedSource(String)

    public var errorDescription: String? {
        switch self {
        case .missingSummaryReference:
            "Planning problem generation requires a summary artifact ID or project-relative summary path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .duplicateArtifactReference(let runID, let artifactID, let count):
            "Run \(runID) contains \(count) artifacts with artifactID \(artifactID); planning problem generation requires a unique artifact reference."
        case .artifactIntegrityFailed(let artifactID, let path, let status, let message):
            "Planning problem source artifact \(artifactID ?? path) failed integrity verification with status \(status.rawValue): \(message)"
        case .explicitPathNotFound(let path):
            "Planning problem generation explicit path does not exist: \(path)."
        case .unsupportedSource(let source):
            "Unsupported planning problem source: \(source)."
        }
    }
}
