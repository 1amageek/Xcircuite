import Foundation

public enum XcircuiteRuntimeError: Error, LocalizedError, Equatable {
    case artifactOutsideProject(path: String, projectRoot: String)
    case artifactReferenceAmbiguous(stageID: String, matchCount: Int)
    case artifactReferenceByteCountMismatch(path: String, expected: Int64, actual: Int64)
    case artifactReferenceDigestMismatch(path: String, expected: String, actual: String)
    case artifactReferenceMissingByteCount(path: String)
    case artifactReferenceMissingDigest(path: String)
    case artifactReferenceNotFound(stageID: String)
    case invalidInputReference(String)
    case inputReferenceMissing(String)
    case invalidConfiguration(String)
    case stageMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .artifactOutsideProject(let path, let projectRoot):
            "Produced artifact is outside the project root: \(path) is not under \(projectRoot)"
        case .artifactReferenceAmbiguous(let stageID, let matchCount):
            "Flow input artifact reference for stage \(stageID) matched \(matchCount) artifacts."
        case .artifactReferenceByteCountMismatch(let path, let expected, let actual):
            "Flow input artifact byte count mismatch for \(path): expected \(expected), got \(actual)."
        case .artifactReferenceDigestMismatch(let path, let expected, let actual):
            "Flow input artifact digest mismatch for \(path): expected \(expected), got \(actual)."
        case .artifactReferenceMissingByteCount(let path):
            "Flow input artifact reference has no byte count: \(path)"
        case .artifactReferenceMissingDigest(let path):
            "Flow input artifact reference has no SHA-256 digest: \(path)"
        case .artifactReferenceNotFound(let stageID):
            "Flow input artifact reference did not match any artifact in stage \(stageID)."
        case .invalidInputReference(let reference):
            "Invalid flow input reference: \(reference)"
        case .inputReferenceMissing(let path):
            "Flow input reference does not exist: \(path)"
        case .invalidConfiguration(let detail):
            "Invalid Xcircuite runtime configuration: \(detail)"
        case .stageMismatch(let expected, let actual):
            "Stage executor mismatch: expected \(expected), got \(actual)"
        }
    }
}
