import Foundation

public enum PDKExternalInspectionProcessError: Error, Sendable, Hashable, LocalizedError {
    case missingProjectRoot
    case invalidStageID(String)
    case invalidRunID(String)
    case invalidAssetID(String)
    case executableMeasurementFailed(path: String, reason: String)
    case artifactPreparationFailed(path: String, reason: String)
    case resultMissing(path: String)
    case resultReadFailed(path: String, reason: String)
    case nonZeroExit(Int32)
    case cancelled
    case timedOut(Double)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            "External PDK inspection requires an explicit project root."
        case .invalidStageID(let stageID):
            "External PDK inspection stage ID is invalid: \(stageID)."
        case .invalidRunID(let runID):
            "External PDK inspection run ID is invalid: \(runID)."
        case .invalidAssetID(let assetID):
            "External PDK inspection asset ID is invalid: \(assetID)."
        case .executableMeasurementFailed(let path, let reason):
            "External PDK inspection executable could not be measured at \(path): \(reason)"
        case .artifactPreparationFailed(let path, let reason):
            "External PDK inspection artifact preparation failed at \(path): \(reason)"
        case .resultMissing(let path):
            "External PDK inspection did not produce a result at \(path)."
        case .resultReadFailed(let path, let reason):
            "External PDK inspection result could not be read at \(path): \(reason)"
        case .nonZeroExit(let exitCode):
            "External PDK inspection process exited with code \(exitCode)."
        case .cancelled:
            "External PDK inspection process was cancelled."
        case .timedOut(let timeout):
            "External PDK inspection process timed out after \(timeout) seconds."
        case .processFailed(let message):
            "External PDK inspection process failed: \(message)"
        }
    }
}
