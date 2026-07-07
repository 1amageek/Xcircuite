import Foundation
import XcircuitePackage

public enum XcircuiteCandidatePlanGenerationError: Error, LocalizedError, Equatable {
    case missingProblemReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String)
    case runMismatch(expected: String, actual: String)
    case invalidRejectedPlanJSONLine(path: String, line: Int)
    case invalidParetoCandidateJSONLine(path: String, line: Int)
    case invalidCalibrationPolicy(String)
    case emptyStrategyFamily
    case invalidPlannerFamilyRunID(String)
    case familyRunAlreadyExists(runID: String, familyRunID: String, path: String)
    case familyRunOutputInspectionFailed(path: String, reason: String)
    case unsupportedPlannerFamilySelectionPolicy(String)
    case noObjectives
    case noCandidateAction(objectiveID: String)

    public var errorDescription: String? {
        switch self {
        case .missingProblemReference:
            "Candidate plan generation requires a planning problem artifact ID or path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Candidate plan artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Candidate plan artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Candidate plan artifact producer run mismatch: expected \(expected), got \(actual)."
        case .runMismatch(let expected, let actual):
            "Candidate plan run mismatch: expected \(expected), got \(actual)."
        case .invalidRejectedPlanJSONLine(let path, let line):
            "Rejected plan feedback file \(path) contains invalid JSON at line \(line)."
        case .invalidParetoCandidateJSONLine(let path, let line):
            "Pareto candidate artifact \(path) contains invalid JSON at line \(line)."
        case .invalidCalibrationPolicy(let value):
            "Candidate plan generation calibrationPolicy must be disabled or cp7-feedback, got \(value)."
        case .emptyStrategyFamily:
            "Symbolic planner family run requires at least one strategy."
        case .invalidPlannerFamilyRunID(let value):
            "Symbolic planner familyRunID is invalid: \(value)."
        case .familyRunAlreadyExists(let runID, let familyRunID, let path):
            "Symbolic planner family run \(familyRunID) for run \(runID) already has output at \(path)."
        case .familyRunOutputInspectionFailed(let path, let reason):
            "Symbolic planner family run output at \(path) could not be inspected: \(reason)"
        case .unsupportedPlannerFamilySelectionPolicy(let value):
            "Symbolic planner family selectionPolicy is not supported: \(value)."
        case .noObjectives:
            "Candidate plan generation requires at least one planning objective."
        case .noCandidateAction(let objectiveID):
            "No candidate action is available for objective \(objectiveID)."
        }
    }
}
