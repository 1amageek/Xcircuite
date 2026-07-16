import Foundation
import DesignFlowKernel

public enum XcircuiteNumericRepairLoopError: Error, LocalizedError, Equatable {
    case invalidMaxCandidates(Int)
    case invalidMaxIterations(Int)
    case invalidCalibrationPolicy(String)
    case archiveArtifactAlreadyExists(path: String)
    case sourceArtifactIntegrityFailed(
        artifactID: String?,
        path: String,
        status: FlowArtifactVerificationStatus,
        message: String
    )
    case duplicateIterationIndex(Int)
    case nonSequentialIterationIndex(expected: Int, actual: Int)
    case resultInvariantViolation(field: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidMaxCandidates(let value):
            "Numeric repair loop maxCandidates must be greater than zero, got \(value)."
        case .invalidMaxIterations(let value):
            "Numeric repair loop maxIterations must be greater than zero, got \(value)."
        case .invalidCalibrationPolicy(let value):
            "Numeric repair loop calibrationPolicy must be disabled or cp7-feedback, got \(value)."
        case .archiveArtifactAlreadyExists(let path):
            "Numeric repair loop archive artifact already exists and will not be overwritten: \(path)."
        case .sourceArtifactIntegrityFailed(let artifactID, let path, let status, let message):
            "Numeric repair loop source artifact \(artifactID ?? path) failed integrity verification with status \(status.rawValue): \(message)"
        case .duplicateIterationIndex(let value):
            "Numeric repair loop contains duplicate iteration index \(value)."
        case .nonSequentialIterationIndex(let expected, let actual):
            "Numeric repair loop iteration index must be sequential; expected \(expected), got \(actual)."
        case .resultInvariantViolation(let field, let expected, let actual):
            "Numeric repair loop result invariant \(field) is invalid; expected \(expected), got \(actual)."
        }
    }
}
