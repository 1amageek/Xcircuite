import Foundation
import XcircuitePackage

public enum XcircuiteSymbolicPlannerPlanImportError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case missingPDDLExportReference
    case missingSolverPlanReference
    case artifactNotFound(runID: String, artifactID: String)
    case artifactIntegrityFailed(
        field: String,
        artifactID: String?,
        path: String,
        status: XcircuiteFileReferenceIntegrityStatus,
        message: String
    )
    case manifestReferenceMismatch(
        field: String,
        artifactID: String,
        path: String,
        manifestPath: String,
        reason: String
    )
    case runMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "Symbolic planner plan import requires a planning problem artifact ID or path."
        case .missingPDDLExportReference:
            "Symbolic planner plan import requires a PDDL export artifact ID or path."
        case .missingSolverPlanReference:
            "Symbolic planner plan import requires solver plan text, artifact ID, or path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .artifactIntegrityFailed(let field, let artifactID, let path, let status, let message):
            "Symbolic planner plan import artifact reference \(field) \(artifactID ?? path) failed integrity verification at \(path) with status \(status.rawValue): \(message)"
        case .manifestReferenceMismatch(let field, let artifactID, let path, let manifestPath, let reason):
            "Symbolic planner plan import artifact reference \(field) \(artifactID) at \(path) does not match run manifest path \(manifestPath): \(reason)"
        case .runMismatch(let expected, let actual):
            "Symbolic planner plan import run mismatch: expected \(expected), got \(actual)."
        }
    }
}
