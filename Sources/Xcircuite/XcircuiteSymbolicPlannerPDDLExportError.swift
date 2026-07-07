import Foundation
import XcircuitePackage

public enum XcircuiteSymbolicPlannerPDDLExportError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case artifactNotFound(runID: String, artifactID: String)
    case duplicateArtifactReference(runID: String, artifactID: String, count: Int)
    case invalidArtifactReference(field: String, path: String, reason: String)
    case artifactIntegrityFailed(
        field: String,
        artifactID: String?,
        path: String,
        status: XcircuiteFileReferenceIntegrityStatus,
        message: String
    )
    case runMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "Symbolic planner PDDL export requires a planning problem artifact ID or path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .duplicateArtifactReference(let runID, let artifactID, let count):
            "Run \(runID) contains \(count) references for artifact \(artifactID)."
        case .invalidArtifactReference(let field, let path, let reason):
            "Symbolic planner PDDL export has invalid \(field) artifact reference at \(path): \(reason)."
        case .artifactIntegrityFailed(let field, let artifactID, let path, let status, let message):
            "Symbolic planner PDDL export \(field) artifact integrity failed for \(artifactID ?? "unidentified artifact") at \(path): \(status.rawValue). \(message)"
        case .runMismatch(let expected, let actual):
            "Symbolic planner PDDL export run mismatch: expected \(expected), got \(actual)."
        }
    }
}
